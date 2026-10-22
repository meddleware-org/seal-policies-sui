#!/usr/bin/env bash
# Shared helpers for upgrade.sh and migrate.sh (sourced, not executed). The same preflight rules as
# publish.sh / transfer-authority.sh / make-immutable.sh: active env, chain identifier, CLI version,
# MAINNET_CONFIRM on mainnet, and an optional EXPECTED_SIGNER (required on mainnet).

log() { printf '%s\n' "$*" >&2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLISHED_TOML="$REPO_ROOT/Published.toml"
# shellcheck disable=SC2034  # used by the scripts that source this file
DEPLOYMENTS="$REPO_ROOT/deployments.json"

long_addr() { local h="${1#0x}"; printf '0x%064s' "${h,,}" | tr ' ' 0; }

# Localnet is an ephemeral network: `publish.sh localnet` uses `test-publish`, which records the publication
# in the git-ignored Pub.localnet.toml (override: PUB_FILE) and the ids in the git-ignored .env.localnet,
# never in the committed Published.toml / deployments.json. testnet/mainnet keep using those two files.
PUB_FILE="${PUB_FILE:-$REPO_ROOT/Pub.localnet.toml}"

published_field() {
  if [ "${NETWORK:-}" = "localnet" ]; then
    # [[published]] entries; ours is the one whose `source = { local = "<this checkout>" }`.
    awk -v root="$REPO_ROOT" -v key="$1" '
      /^\[\[published\]\]/ { mine = 0; next }
      /^\[/                { mine = 0 }
      $0 ~ "^[[:space:]]*source[[:space:]]*=" { mine = (index($0, "local = \"" root "\"") > 0); next }
      mine && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
        gsub(/.*=[[:space:]]*"/, ""); gsub(/".*/, ""); print; exit
      }
    ' "$PUB_FILE" 2>/dev/null || true
    return 0
  fi
  awk -v section="[published.${NETWORK}]" -v key="$1" '
    $0 == section { in_section = 1; next }
    /^\[/         { in_section = 0 }
    in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      gsub(/.*=[[:space:]]*"/, ""); gsub(/".*/, ""); print; exit
    }
  ' "$PUBLISHED_TOML" 2>/dev/null || true
}

# A deployment id: deployments.json (committed record) for testnet/mainnet; on localnet the git-ignored
# .env.localnet written by publish.sh. $1 = deployments.json key, $2 = .env variable.
deployment_id() {
  if [ "${NETWORK:-}" = "localnet" ]; then
    if [ -f "$REPO_ROOT/.env.localnet" ]; then sed -n "s/^$2=//p" "$REPO_ROOT/.env.localnet" | head -1; fi
    return 0
  fi
  jq -r --arg n "$NETWORK" --arg k "$1" '.[$n][$k] // empty' "$DEPLOYMENTS" 2>/dev/null || true
}

# The VERSION constant compiled into this checkout (sources/config.move).
source_version() { sed -n 's/^const VERSION: u64 = \([0-9][0-9]*\);.*/\1/p' "$REPO_ROOT/sources/config.move" | head -1; }

# The version the shared PolicyConfig names on-chain.
onchain_version() {
  sui client object "$1" --json 2>/dev/null | jq -r '.content.fields.version // .content.version // empty'
}

# The package the UpgradeCap currently names, i.e. the latest published version (empty if the cap is gone).
latest_package_id() {
  # `sui client object` exits non-zero for a deleted (burned) object: that is "empty", not a failure.
  { sui client object "$1" --json 2>/dev/null || true; } | jq -r '.content.package // empty'
}

# Refuse unless $1 (the recorded published-at) is the latest version: a stale record would aim `migrate` at
# the old package, or let `--verify` bless it. The cap is gone after make-immutable: then only a note.
require_latest_package() {
  local cap latest
  cap="$(published_field upgrade-capability)"
  latest=""
  if [ -n "$cap" ]; then latest="$(latest_package_id "$cap")"; fi
  if [ -z "$latest" ]; then
    log "NOTE: the UpgradeCap '${cap:-<none recorded>}' was not found (burned?): cannot confirm $1 is the latest version."
    return 0
  fi
  [ "$(long_addr "$latest")" = "$(long_addr "$1")" ] || {
    log "ERROR: the recorded published-at $1 is not the latest version: the UpgradeCap names $latest."
    log "       Record the upgraded published-at first (CUSTODY.md, 'Upgrading during the verification window', step 2)."
    exit 1
  }
}

preflight() {
  local env chain want tool cli
  command -v jq >/dev/null || { log "ERROR: jq is required"; exit 1; }
  env="$(sui client active-env 2>/dev/null || true)"
  [ "$env" = "$NETWORK" ] || { log "ERROR: active Sui env is '${env:-<none>}', expected '$NETWORK' (sui client switch --env $NETWORK)."; exit 1; }
  case "$NETWORK" in testnet) want=4c78adac ;; mainnet) want=35834a8a ;; *) want="" ;; esac
  if [ -n "$want" ]; then
    chain="$(sui client chain-identifier 2>/dev/null | awk '/^Hex:/{print $2; exit} !/:/{print $1; exit}')"
    [ "$chain" = "$want" ] || { log "ERROR: chain identifier is '${chain:-<unreachable>}', expected $want for $NETWORK."; exit 1; }
  fi
  tool="$(published_field toolchain-version)"
  cli="$(sui --version | awk '{print $2}' | cut -d- -f1)"
  if [ -n "$tool" ] && [ "${cli%.*}" != "${tool%.*}" ]; then
    if [ "${ALLOW_TOOLCHAIN_CHANGE:-}" = "1" ]; then
      # An upgrade must be built by a CLI that knows the network's current protocol version (`protocol version N
      # is newer than the maximum version M supported by this CLI`), which can be newer than the one that published.
      log "WARNING: running sui CLI $cli instead of the recorded $tool (ALLOW_TOOLCHAIN_CHANGE=1)."
    else
      log "ERROR: sui CLI $cli does not match Published.toml toolchain-version $tool (major.minor)."
      log "       For a deliberate move to a newer CLI (the network's protocol version outgrew the recorded one), re-run with ALLOW_TOOLCHAIN_CHANGE=1."
      exit 1
    fi
  fi
  if [ "$NETWORK" = "mainnet" ] && [ "${MAINNET_CONFIRM:-}" != "1" ]; then
    log "SKIPPED: mainnet — re-run with MAINNET_CONFIRM=1 to proceed."; exit 78
  fi
}

# EXPECTED_SIGNER guards scripts that act as the ACTIVE address (publish, transfer). Scripts that only
# build an unsigned transaction for a multisig do not need the active key to be anyone in particular.
expect_signer() {
  local active
  active="$(sui client active-address)"
  if [ -n "${EXPECTED_SIGNER:-}" ]; then
    [[ "$EXPECTED_SIGNER" =~ ^0x[0-9a-fA-F]{1,64}$ ]] || { log "ERROR: EXPECTED_SIGNER must be a 0x-prefixed address."; exit 1; }
    [ "$(long_addr "$EXPECTED_SIGNER")" = "$(long_addr "$active")" ] \
      || { log "ERROR: the active address $active is not EXPECTED_SIGNER $EXPECTED_SIGNER."; exit 1; }
  elif [ "$NETWORK" = "mainnet" ]; then
    log "ERROR: mainnet requires EXPECTED_SIGNER."; exit 1
  fi
}
