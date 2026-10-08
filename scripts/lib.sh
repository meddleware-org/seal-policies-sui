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

published_field() {
  awk -v section="[published.${NETWORK}]" -v key="$1" '
    $0 == section { in_section = 1; next }
    /^\[/         { in_section = 0 }
    in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      gsub(/.*=[[:space:]]*"/, ""); gsub(/".*/, ""); print; exit
    }
  ' "$PUBLISHED_TOML" 2>/dev/null || true
}

# The VERSION constant compiled into this checkout (sources/config.move).
source_version() { sed -n 's/^const VERSION: u64 = \([0-9][0-9]*\);.*/\1/p' "$REPO_ROOT/sources/config.move" | head -1; }

# The version the shared PolicyConfig names on-chain.
onchain_version() {
  sui client object "$1" --json 2>/dev/null | jq -r '.content.fields.version // .content.version // empty'
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
    log "ERROR: sui CLI $cli does not match Published.toml toolchain-version $tool (major.minor)."; exit 1
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
