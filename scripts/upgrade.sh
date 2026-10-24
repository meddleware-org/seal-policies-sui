#!/usr/bin/env bash
# Prepare an UPGRADE of the published sealed_storage package for the custody multisig (CUSTODY.md,
# "Upgrading during the verification window"). Nothing is signed or executed here: the script checks
# everything it can, then writes the unsigned upgrade transaction (sender = the multisig).
#
# Checks (all hard failures):
#   - the shared preflight (active env, chain identifier, CLI version, MAINNET_CONFIRM);
#   - `VERSION` in sources/config.move is GREATER than the version the on-chain PolicyConfig names
#     (a forgotten bump would leave the faulty seal_approve* live after `migrate`);
#   - the UpgradeCap (Published.toml `upgrade-capability`) exists and is owned by MULTISIG_ADDRESS.
#
# Usage:
#   NETWORK=testnet MULTISIG_ADDRESS=0x<64hex> bash scripts/upgrade.sh
# Output: $REPO_ROOT/upgrade.<network>.tx.b64 (gitignored), then the signing steps of CUSTODY.md.
# After the multisig executes it: scripts/migrate.sh (prepare), execute, then scripts/migrate.sh --verify.

set -euo pipefail
NETWORK="${NETWORK:-testnet}"
GAS_BUDGET="${GAS_BUDGET:-300000000}"
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MULTISIG_ADDRESS="${MULTISIG_ADDRESS:-}"
[[ "$MULTISIG_ADDRESS" =~ ^0x[0-9a-fA-F]{64}$ ]] || { log "ERROR: MULTISIG_ADDRESS must be set to a 0x-prefixed 64-hex address."; exit 1; }
preflight

POLICY_CONFIG_ID="$(deployment_id policyConfigId SEAL_POLICIES_POLICY_CONFIG_ID)"
[ -n "$POLICY_CONFIG_ID" ] || { log "ERROR: no policyConfigId for $NETWORK in deployments.json (localnet: .env.localnet)."; exit 1; }
UPGRADE_CAP_ID="$(published_field upgrade-capability)"
[ -n "$UPGRADE_CAP_ID" ] || { log "ERROR: no upgrade-capability for $NETWORK in Published.toml (localnet: $PUB_FILE)."; exit 1; }

SRC_VERSION="$(source_version)"
CHAIN_VERSION="$(onchain_version "$POLICY_CONFIG_ID")"
[[ "$SRC_VERSION" =~ ^[0-9]+$ ]] || { log "ERROR: cannot read VERSION from sources/config.move."; exit 1; }
[[ "$CHAIN_VERSION" =~ ^[0-9]+$ ]] || { log "ERROR: cannot read the on-chain PolicyConfig version of $POLICY_CONFIG_ID."; exit 1; }
if [ "$SRC_VERSION" -le "$CHAIN_VERSION" ]; then
  log "ERROR: VERSION in sources/config.move is $SRC_VERSION, the on-chain PolicyConfig is at $CHAIN_VERSION."
  log "       An upgrade that must retire the old code needs VERSION > $CHAIN_VERSION (then migrate)."
  exit 1
fi

CAP_JSON="$(sui client object "$UPGRADE_CAP_ID" --json 2>/dev/null)" || { log "ERROR: UpgradeCap $UPGRADE_CAP_ID not found on $NETWORK."; exit 1; }
CAP_OWNER="$(jq -r '.owner.AddressOwner // empty' <<<"$CAP_JSON")"
[ "$(long_addr "$CAP_OWNER")" = "$(long_addr "$MULTISIG_ADDRESS")" ] \
  || { log "ERROR: UpgradeCap $UPGRADE_CAP_ID is owned by '${CAP_OWNER:-<not address-owned>}', not MULTISIG_ADDRESS."; exit 1; }

OUT_FILE="$REPO_ROOT/upgrade.${NETWORK}.tx.b64"
log "Building the unsigned upgrade (sender = the multisig; VERSION $CHAIN_VERSION -> $SRC_VERSION) ..."
# `sui client upgrade` needs the network in Move.toml (testnet/mainnet); localnet is ephemeral and uses
# `test-upgrade` against the Pub.localnet.toml that `publish.sh localnet` wrote.
if [ "$NETWORK" = "localnet" ]; then
  [ -f "$PUB_FILE" ] || { log "ERROR: $PUB_FILE not found (written by scripts/publish.sh localnet)."; exit 1; }
  UPGRADE_CMD=(sui client test-upgrade --build-env testnet --pubfile-path "$PUB_FILE")
else
  UPGRADE_CMD=(sui client upgrade)
fi
# The CLI prints its diagnostics on stdout (not stderr): keep both and show both on failure.
( cd "$REPO_ROOT" && "${UPGRADE_CMD[@]}" --upgrade-capability "$UPGRADE_CAP_ID" --sender "$MULTISIG_ADDRESS" \
    --gas-budget "$GAS_BUDGET" --serialize-unsigned-transaction ) > "$OUT_FILE.raw" 2> "$OUT_FILE.log" \
  || { log "ERROR: building the upgrade failed:"; cat "$OUT_FILE.raw" "$OUT_FILE.log" >&2; rm -f "$OUT_FILE.raw"; exit 1; }
tail -n 1 "$OUT_FILE.raw" > "$OUT_FILE" && rm -f "$OUT_FILE.raw"
[[ "$(cat "$OUT_FILE")" =~ ^[A-Za-z0-9+/]+=*$ ]] || { log "ERROR: the CLI did not end with transaction bytes:"; cat "$OUT_FILE" "$OUT_FILE.log" >&2; rm -f "$OUT_FILE"; exit 1; }

log "Wrote $OUT_FILE"
log ""
log "Next (CUSTODY.md, 'Signing a transaction as the multisig'):"
log "  1. each signer: sui keytool sign --address <signer> --data \"\$(cat $OUT_FILE)\" --json"
log "  2. combine:     sui keytool multi-sig-combine-partial-sig --pks … --weights … --threshold … --sigs … --json"
log "  3. execute:     sui client execute-signed-tx --tx-bytes \"\$(cat $OUT_FILE)\" --signatures <multisigSerialized>"
if [ "$NETWORK" = "localnet" ]; then RECORD_FILE="${PUB_FILE##*/}"; else RECORD_FILE="Published.toml"; fi
log "  4. record the new published-at in $RECORD_FILE, then: NETWORK=$NETWORK MULTISIG_ADDRESS=$MULTISIG_ADDRESS bash scripts/migrate.sh"
