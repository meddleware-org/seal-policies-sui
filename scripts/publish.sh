#!/usr/bin/env bash
# =============================================================================
# seal_policies — fresh publish
# =============================================================================
# Publishes the seal_policies package and records every authority object by its exact type:
#   - .env.<network>     (gitignored) package, UpgradeCap, PolicyAdminCap and PolicyConfig ids
#   - deployments.json   (committed)  the shared PolicyConfig id and the custody record (CUSTODY.md)
#   - Published.toml     (committed)  written by Sui: published-at, original-id, upgrade-capability
#
# Usage:
#   ./scripts/publish.sh <localnet|testnet|mainnet> [--replace-published]
#
#   --replace-published  Fresh republish over an existing Published.toml entry for <network> (the old
#                        entry is backed up and removed; every ID changes).
#
# Localnet uses `test-publish --build-env testnet --publish-unpublished-deps` (Move.toml declares only
# testnet/mainnet), which also publishes access_gate there.
# On testnet/mainnet, access_gate must already be published at the commit Move.toml pins.
#
# Safety (preflight, before anything is signed):
#   - the ACTIVE `sui client` env must already be <network> (never switched here);
#   - testnet/mainnet: the chain identifier must match the network;
#   - the `sui` CLI major.minor must match Published.toml `toolchain-version` (ALLOW_TOOLCHAIN_CHANGE=1
#     permits a deliberate move to a new toolchain, which the fresh publish then records);
#   - mainnet additionally requires MAINNET_CONFIRM=1 (a skipped run exits 78).
# An existing .env.<network> is kept as .env.<network>.<timestamp>.bak, never overwritten.
#
# Also checked before anything is signed (testnet/mainnet):
#   - EXPECTED_SIGNER (0x… address), when set, must equal the active address; mainnet requires it;
#   - the active address holds at least GAS_BUDGET MIST;
#   - the access_gate dependency pinned in Move.toml has a publication on THIS chain (its Published.toml at
#     the pinned commit), so the package links the real access_gate and not a stray copy.
# After publishing: the new package's linkage table must map access_gate's original id to that
# publication, and the package must contain no module of its own named access_gate. deployments.json is
# written only after both pass.
#
# Env: GAS_BUDGET (default 200000000).
# -----------------------------------------------------------------------------
set -euo pipefail

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >&2; }
trap 'log "ERROR: publish.sh failed at line $LINENO (exit $?)."' ERR

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NETWORK="${1:-}"
case "$NETWORK" in
  localnet|testnet|mainnet) ;;
  *) log "Usage: ./scripts/publish.sh <localnet|testnet|mainnet> [--replace-published]"; exit 1 ;;
esac
REPLACE_PUBLISHED=""
for _arg in "${@:2}"; do
  case "$_arg" in
    --replace-published) REPLACE_PUBLISHED="1" ;;
    *) log "ERROR: unknown argument '${_arg}'."; exit 1 ;;
  esac
done
GAS_BUDGET="${GAS_BUDGET:-200000000}"
ENV_FILE="$PKG_DIR/.env.${NETWORK}"
command -v jq >/dev/null || { log "ERROR: jq is required"; exit 1; }

# ── Preflight ────────────────────────────────────────────────────────────────────
# Published.toml `toolchain-version` for a network (falls back to the testnet record).
toolchain_version() {
  local v
  v=$(awk -v s="[published.$1]" '$0==s{f=1;next} /^\[/{f=0} f && /^toolchain-version/{gsub(/.*= *"|".*/,"");print;exit}' "$PKG_DIR/Published.toml" 2>/dev/null)
  [ -n "$v" ] || v=$(awk '$0=="[published.testnet]"{f=1;next} /^\[/{f=0} f && /^toolchain-version/{gsub(/.*= *"|".*/,"");print;exit}' "$PKG_DIR/Published.toml" 2>/dev/null)
  echo "$v"
}
ACTIVE_ENV=$(sui client active-env 2>/dev/null || true)
[ "$ACTIVE_ENV" = "$NETWORK" ] || { log "ERROR: the active Sui env is '${ACTIVE_ENV:-<none>}', not '${NETWORK}' (sui client switch --env ${NETWORK})."; exit 1; }
case "$NETWORK" in testnet) WANT_CHAIN=4c78adac ;; mainnet) WANT_CHAIN=35834a8a ;; *) WANT_CHAIN="" ;; esac
if [ -n "$WANT_CHAIN" ]; then
  CHAIN=$(sui client chain-identifier 2>/dev/null | awk '/^Hex:/{print $2; exit} !/:/{print $1; exit}')
  [ "$CHAIN" = "$WANT_CHAIN" ] || { log "ERROR: chain identifier is '${CHAIN:-<unreachable>}', expected ${WANT_CHAIN} for ${NETWORK}."; exit 1; }
fi
WANT_TOOL=$(toolchain_version "$NETWORK")
CLI_VER=$(sui --version | awk '{print $2}' | cut -d- -f1)
if [ -n "$WANT_TOOL" ] && [ "${CLI_VER%.*}" != "${WANT_TOOL%.*}" ]; then
  if [ "${ALLOW_TOOLCHAIN_CHANGE:-}" = "1" ]; then
    log "WARNING: publishing with sui CLI ${CLI_VER} instead of the recorded ${WANT_TOOL} (ALLOW_TOOLCHAIN_CHANGE=1)."
  else
    log "ERROR: sui CLI ${CLI_VER} does not match Published.toml toolchain-version ${WANT_TOOL} (major.minor);"
    log "       switch CLI, or re-run with ALLOW_TOOLCHAIN_CHANGE=1 for a deliberate move to a new toolchain."
    exit 1
  fi
fi
if [ "$NETWORK" = "mainnet" ] && [ "${MAINNET_CONFIRM:-}" != "1" ]; then
  log "SKIPPED: mainnet — re-run with MAINNET_CONFIRM=1 to proceed."
  exit 78
fi
DEPLOYER=$(sui client active-address)
norm_addr() { local h="${1#0x}"; printf '0x%064s' "${h,,}" | tr ' ' 0; }
if [ -n "${EXPECTED_SIGNER:-}" ]; then
  [[ "$EXPECTED_SIGNER" =~ ^0x[0-9a-fA-F]{1,64}$ ]] || { log "ERROR: EXPECTED_SIGNER must be a 0x-prefixed address."; exit 1; }
  [ "$(norm_addr "$EXPECTED_SIGNER")" = "$(norm_addr "$DEPLOYER")" ] \
    || { log "ERROR: the active address ${DEPLOYER} is not EXPECTED_SIGNER ${EXPECTED_SIGNER}."; exit 1; }
elif [ "$NETWORK" = "mainnet" ]; then
  log "ERROR: mainnet requires EXPECTED_SIGNER."; exit 1
fi
BALANCE=$(sui client gas --json 2>/dev/null | jq -r '([.gasCoins[]?.mistBalance] | add // 0) + (.addressMistBalance // 0)')
[[ "$BALANCE" =~ ^[0-9]+$ ]] || { log "ERROR: could not read the gas balance of ${DEPLOYER}."; exit 1; }
[ "$BALANCE" -ge "$GAS_BUDGET" ] || { log "ERROR: ${DEPLOYER} holds ${BALANCE} MIST, less than GAS_BUDGET=${GAS_BUDGET}."; exit 1; }
log "Preflight OK: env=${NETWORK} chain=${CHAIN:-n/a} cli=${CLI_VER} signer=${DEPLOYER} balance=${BALANCE} MIST"

# The access_gate publication this package links (testnet/mainnet): read from the dependency's own
# Published.toml at the commit Move.toml pins, and require it to exist on this chain.
AG_ORIGINAL=""; AG_PUBLISHED=""
if [ "$NETWORK" != "localnet" ]; then
  AG_REV=$(sed -n 's/^access_gate = .*rev = "\([0-9a-f]\{40\}\)".*/\1/p' "$PKG_DIR/Move.toml" | head -1)
  [ -n "$AG_REV" ] || { log "ERROR: Move.toml does not pin access_gate to a 40-hex commit (a local or branch dependency cannot be published)."; exit 1; }
  AG_TOML=$(curl -fsSL --max-time 20 "https://raw.githubusercontent.com/meddleware-org/access-gate-sui/${AG_REV}/Published.toml") \
    || { log "ERROR: could not read access-gate-sui Published.toml at ${AG_REV}."; exit 1; }
  ag_field() { awk -v s="[published.${NETWORK}]" -v k="$1" '$0==s{f=1;next} /^\[/{f=0} f && $0 ~ "^[[:space:]]*" k "[[:space:]]*="{gsub(/.*= *"|".*/,"");print;exit}' <<<"$AG_TOML"; }
  AG_ORIGINAL=$(ag_field original-id); AG_PUBLISHED=$(ag_field published-at)
  [[ -n "$AG_ORIGINAL" && -n "$AG_PUBLISHED" ]] || { log "ERROR: access-gate-sui ${AG_REV} records no ${NETWORK} publication."; exit 1; }
  sui client object "$AG_PUBLISHED" --json >/dev/null 2>&1 || { log "ERROR: access_gate ${AG_PUBLISHED} does not exist on ${NETWORK}."; exit 1; }
  log "access_gate dependency: ${AG_PUBLISHED} (original ${AG_ORIGINAL}) at ${AG_REV:0:7}"
fi

# ── Publish ──────────────────────────────────────────────────────────────────────
# A network with a Published.toml entry is already published; `sui client publish` refuses until the
# entry is removed. --replace-published makes a deliberate fresh republish: the old entry is kept in a
# gitignored Published.toml.<timestamp>.bak and removed (git history also keeps it).
if [ "$NETWORK" != "localnet" ] && grep -qx "\[published.${NETWORK}\]" "$PKG_DIR/Published.toml" 2>/dev/null; then
  if [ "$REPLACE_PUBLISHED" != "1" ]; then
    log "ERROR: Published.toml already records a ${NETWORK} publication. Upgrade it, or re-run with"
    log "       --replace-published for a deliberate fresh publish (new package and object IDs)."
    exit 1
  fi
  cp "$PKG_DIR/Published.toml" "$PKG_DIR/Published.toml.$(date -u +%Y%m%dT%H%M%SZ).bak"
  awk -v s="[published.${NETWORK}]" '$0==s{skip=1;next} /^\[/{skip=0} !skip' "$PKG_DIR/Published.toml" > "$PKG_DIR/Published.toml.tmp"
  mv "$PKG_DIR/Published.toml.tmp" "$PKG_DIR/Published.toml"
  log "Removed the previous ${NETWORK} entry from Published.toml (backup kept)."
fi
log "Publishing seal_policies to ${NETWORK} ..."
if [ "$NETWORK" = "localnet" ]; then
  PUBFILE="$(mktemp -d)/Pub.localnet.toml"   # must not exist yet: test-publish creates it
  OUT=$(sui client test-publish "$PKG_DIR" --json --build-env testnet --pubfile-path "$PUBFILE" \
    --publish-unpublished-deps --gas-budget "$GAS_BUDGET" 2>&1) || { log "ERROR: test-publish failed"; log "$OUT"; exit 1; }
else
  OUT=$(sui client publish "$PKG_DIR" --json --gas-budget "$GAS_BUDGET" 2>&1) || { log "ERROR: publish failed"; log "$OUT"; exit 1; }
fi
# --publish-unpublished-deps prints one JSON document per published package; ours is the last.
JSON=$(awk '/^{/{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' <<<"$OUT")
jq -e '.objectChanges' >/dev/null 2>&1 <<<"$JSON" || { log "ERROR: publish output has no objectChanges; refusing to guess object IDs."; log "$OUT"; exit 1; }

PACKAGE_ID=$(jq -r '[.objectChanges[] | select(.type=="published") | .packageId] | if length==1 then .[0] else "" end' <<<"$JSON")
[ -n "$PACKAGE_ID" ] || { log "ERROR: could not find exactly one published package"; exit 1; }
created_id() {
  jq -r --arg t "$1" '[.objectChanges[] | select(.type=="created" and .objectType==$t) | .objectId] | if length==1 then .[0] else "" end' <<<"$JSON"
}
UPGRADE_CAP_ID=$(created_id "0x2::package::UpgradeCap")
POLICY_ADMIN_CAP_ID=$(created_id "${PACKAGE_ID}::config::PolicyAdminCap")
POLICY_CONFIG_ID=$(created_id "${PACKAGE_ID}::config::PolicyConfig")
for _v in UPGRADE_CAP_ID POLICY_ADMIN_CAP_ID POLICY_CONFIG_ID; do
  [ -n "${!_v}" ] || { log "ERROR: could not find exactly one created object for ${_v}"; exit 1; }
done

# Linkage: the published package must link the expected access_gate and bundle none of its own.
if [ "$NETWORK" != "localnet" ]; then
  PKG_JSON=$(sui client object "$PACKAGE_ID" --json 2>/dev/null) || { log "ERROR: cannot read the published package ${PACKAGE_ID}."; exit 1; }
  LINKED=$(jq -r --arg o "$(norm_addr "$AG_ORIGINAL")" '.content.Package.linkage_table[$o].upgraded_id // empty' <<<"$PKG_JSON")
  [[ -n "$LINKED" && "$(norm_addr "$LINKED")" == "$(norm_addr "$AG_PUBLISHED")" ]] \
    || { log "ERROR: ${PACKAGE_ID} does not link access_gate ${AG_PUBLISHED} (linkage says '${LINKED:-<none>}'). DO NOT USE IT: burn its UpgradeCap."; exit 1; }
  jq -e '.content.Package.module_map | has("access_gate") | not' >/dev/null <<<"$PKG_JSON" \
    || { log "ERROR: ${PACKAGE_ID} bundles its own access_gate module. DO NOT USE IT: burn its UpgradeCap."; exit 1; }
  log "Linkage OK: ${PACKAGE_ID} links access_gate ${AG_PUBLISHED}."
fi

if [ -f "$ENV_FILE" ]; then
  BACKUP="${ENV_FILE}.$(date -u +%Y%m%dT%H%M%SZ).bak"
  mv "$ENV_FILE" "$BACKUP"
  log "Kept the previous record as $BACKUP"
fi
{
  echo "SEAL_POLICIES_PACKAGE_ID=$PACKAGE_ID"
  echo "SEAL_POLICIES_UPGRADE_CAP_ID=$UPGRADE_CAP_ID"
  echo "SEAL_POLICIES_POLICY_ADMIN_CAP_ID=$POLICY_ADMIN_CAP_ID"
  echo "SEAL_POLICIES_POLICY_CONFIG_ID=$POLICY_CONFIG_ID"
} > "$ENV_FILE"
log "Published. packageId=$PACKAGE_ID policyConfigId=$POLICY_CONFIG_ID"
log "Wrote $ENV_FILE"

if [ "$NETWORK" != "localnet" ]; then
  # A fresh publish resets the custody record (CUSTODY.md); a multisig chosen earlier is kept.
  DEPLOYMENTS="$PKG_DIR/deployments.json"
  [ -f "$DEPLOYMENTS" ] || echo '{}' > "$DEPLOYMENTS"
  jq --arg n "$NETWORK" --arg id "$POLICY_CONFIG_ID" --arg owner "$DEPLOYER" --arg pac "$POLICY_ADMIN_CAP_ID" \
    '.[$n].policyConfigId = $id
     | .[$n].policyAdminCapId = $pac
     | .[$n].policyAdminCapOwner = $owner
     | .[$n].custody = { multisigAddress: (.[$n].custody.multisigAddress // null),
                         upgradeCapOwner: $owner, plannedBurnDate: null, burnedAt: null }' \
    "$DEPLOYMENTS" > "$DEPLOYMENTS.tmp"
  mv "$DEPLOYMENTS.tmp" "$DEPLOYMENTS"
  log "Recorded policyConfigId and custody in $DEPLOYMENTS — commit it with Published.toml."
fi
log "Next: transfer the PolicyAdminCap and UpgradeCap to the multisig (scripts/transfer-authority.sh)."
