#!/usr/bin/env bash
# `config::migrate` for the custody multisig, and its verification (CUSTODY.md).
#
#   scripts/migrate.sh            Prepare: write the unsigned `migrate` transaction (sender = the multisig).
#   scripts/migrate.sh --verify   Verify, after it executed: the on-chain PolicyConfig names the VERSION of
#                                 this checkout, and the latest package links the expected access_gate.
#                                 Then print the consumer release steps.
#
# Usage:
#   NETWORK=testnet MULTISIG_ADDRESS=0x<64hex> bash scripts/migrate.sh
#   NETWORK=testnet bash scripts/migrate.sh --verify
# Needs the PolicyAdminCap id (deployments.json `policyAdminCapId`, written by publish.sh) and the latest
# published-at (Published.toml). `migrate` retires EVERY older package version at once, so a slow migrate
# extends the window in which a known-bad version keeps approving: do it right after the upgrade.

set -euo pipefail
NETWORK="${NETWORK:-testnet}"
GAS_BUDGET="${GAS_BUDGET:-100000000}"
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VERIFY=""
for arg in "$@"; do
  case "$arg" in
    --verify) VERIFY="1" ;;
    *) log "ERROR: unknown argument '$arg'."; exit 1 ;;
  esac
done
preflight

POLICY_CONFIG_ID="$(jq -r --arg n "$NETWORK" '.[$n].policyConfigId // empty' "$DEPLOYMENTS" 2>/dev/null || true)"
PACKAGE_ID="$(published_field published-at)"
[[ -n "$POLICY_CONFIG_ID" && -n "$PACKAGE_ID" ]] || { log "ERROR: need policyConfigId (deployments.json) and published-at (Published.toml) for $NETWORK."; exit 1; }
SRC_VERSION="$(source_version)"
CHAIN_VERSION="$(onchain_version "$POLICY_CONFIG_ID")"
[[ "$SRC_VERSION" =~ ^[0-9]+$ && "$CHAIN_VERSION" =~ ^[0-9]+$ ]] || { log "ERROR: cannot read the source or on-chain version."; exit 1; }

if [ -n "$VERIFY" ]; then
  [ "$CHAIN_VERSION" = "$SRC_VERSION" ] || { log "ERROR: PolicyConfig is at version $CHAIN_VERSION, this checkout's VERSION is $SRC_VERSION: migrate has not executed (or the wrong package is recorded)."; exit 1; }
  PKG_JSON="$(sui client object "$PACKAGE_ID" --json 2>/dev/null)" || { log "ERROR: package $PACKAGE_ID not found on $NETWORK."; exit 1; }
  jq -e '.content.Package.module_map | has("nft_gate") and has("timelock") and has("sealed_content") and has("config")' >/dev/null <<<"$PKG_JSON" \
    || { log "ERROR: package $PACKAGE_ID lacks an expected module."; exit 1; }
  jq -e '.content.Package.module_map | has("access_gate") | not' >/dev/null <<<"$PKG_JSON" \
    || { log "ERROR: package $PACKAGE_ID bundles its own access_gate module (a stray copy can never accept a real gate's pass)."; exit 1; }
  log "OK    PolicyConfig $POLICY_CONFIG_ID is at version $CHAIN_VERSION = VERSION; package $PACKAGE_ID is the latest."
  log ""
  log "Consumer release steps (the new published-at changes; original-id and policyConfigId do not):"
  log "  1. commit Published.toml / deployments.json and release @meddleware/seal-policies-sui;"
  log "  2. regenerate @meddleware/seal-client deployments (npm run gen:deployments), release it;"
  log "  3. bump seal-ui and the dashboard; the indexer needs no change (it matches the original id)."
  exit 0
fi

MULTISIG_ADDRESS="${MULTISIG_ADDRESS:-}"
[[ "$MULTISIG_ADDRESS" =~ ^0x[0-9a-fA-F]{64}$ ]] || { log "ERROR: MULTISIG_ADDRESS must be set to a 0x-prefixed 64-hex address."; exit 1; }
POLICY_ADMIN_CAP_ID="$(jq -r --arg n "$NETWORK" '.[$n].policyAdminCapId // empty' "$DEPLOYMENTS" 2>/dev/null || true)"
POLICY_ADMIN_CAP_ID="${POLICY_ADMIN_CAP_ID:-${POLICY_ADMIN_CAP_ID_OVERRIDE:-}}"
[ -n "$POLICY_ADMIN_CAP_ID" ] || { log "ERROR: no policyAdminCapId for $NETWORK in deployments.json."; exit 1; }
[ "$SRC_VERSION" -gt "$CHAIN_VERSION" ] || { log "ERROR: nothing to migrate: PolicyConfig is at $CHAIN_VERSION, VERSION is $SRC_VERSION."; exit 1; }
OWNER="$(sui client object "$POLICY_ADMIN_CAP_ID" --json 2>/dev/null | jq -r '.owner.AddressOwner // empty')"
[ "$(long_addr "$OWNER")" = "$(long_addr "$MULTISIG_ADDRESS")" ] \
  || { log "ERROR: PolicyAdminCap $POLICY_ADMIN_CAP_ID is owned by '${OWNER:-<unknown>}', not MULTISIG_ADDRESS."; exit 1; }

OUT_FILE="$REPO_ROOT/migrate.${NETWORK}.tx.b64"
sui client ptb --move-call "${PACKAGE_ID}::config::migrate" "@${POLICY_ADMIN_CAP_ID}" "@${POLICY_CONFIG_ID}" \
  --sender "@${MULTISIG_ADDRESS}" --gas-budget "$GAS_BUDGET" --serialize-unsigned-transaction > "$OUT_FILE.raw" 2> "$OUT_FILE.log" \
  || { log "ERROR: building migrate failed:"; cat "$OUT_FILE.log" >&2; rm -f "$OUT_FILE.raw"; exit 1; }
tail -n 1 "$OUT_FILE.raw" > "$OUT_FILE" && rm -f "$OUT_FILE.raw"
[ -s "$OUT_FILE" ] || { log "ERROR: no transaction bytes were produced."; exit 1; }
log "Wrote $OUT_FILE (migrate $CHAIN_VERSION -> $SRC_VERSION). Sign and execute it as the multisig (CUSTODY.md),"
log "then run: NETWORK=$NETWORK bash scripts/migrate.sh --verify"
