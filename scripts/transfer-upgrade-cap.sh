#!/usr/bin/env bash
# Transfer the seal_policies UpgradeCap to a multisig / governance address.
#
# Why: this is the alternative to burning the cap (make-immutable.sh). Instead of giving up upgrade
# authority entirely, custody moves from the single deploy EOA to a multisig, so no one key can
# unilaterally upgrade the policy package (which could retroactively de-gate sealed content). Pick
# ONE custody option per network — burn (make-immutable.sh) OR transfer-to-multisig (this script).
#
# Usage:
#   NETWORK=testnet MULTISIG_ADDRESS=0x<64hex> bash scripts/transfer-upgrade-cap.sh            # dry run
#   NETWORK=testnet MULTISIG_ADDRESS=0x<64hex> DRY_RUN=0 bash scripts/transfer-upgrade-cap.sh  # execute
#
# The UpgradeCap id is read from Published.toml (`upgrade-capability` under [published.<network>]),
# or override with UPGRADE_CAP_ID. The active `sui client` address must currently own the cap.

set -euo pipefail

NETWORK="${NETWORK:-testnet}"
DRY_RUN="${DRY_RUN:-1}"
GAS_BUDGET="${GAS_BUDGET:-100000000}"
MULTISIG_ADDRESS="${MULTISIG_ADDRESS:-${1:-}}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLISHED_TOML="$REPO_ROOT/Published.toml"

log() { printf '%s\n' "$*" >&2; }

read_upgrade_cap() {
  awk -v section="[published.${NETWORK}]" '
    $0 == section { in_section = 1; next }
    /^\[/         { in_section = 0 }
    in_section && /^[[:space:]]*upgrade-capability[[:space:]]*=/ {
      gsub(/.*=[[:space:]]*"/, ""); gsub(/".*/, ""); print; exit
    }
  ' "$PUBLISHED_TOML"
}

if [ -z "$MULTISIG_ADDRESS" ]; then
  log "ERROR: MULTISIG_ADDRESS is required (env var or \$1)."
  exit 1
fi

UPGRADE_CAP_ID="${UPGRADE_CAP_ID:-}"
if [ -z "$UPGRADE_CAP_ID" ]; then
  if [ ! -f "$PUBLISHED_TOML" ]; then
    log "ERROR: $PUBLISHED_TOML not found and UPGRADE_CAP_ID not set."
    exit 1
  fi
  UPGRADE_CAP_ID="$(read_upgrade_cap)"
fi

if [ -z "$UPGRADE_CAP_ID" ]; then
  log "ERROR: could not determine UpgradeCap id for network '$NETWORK'."
  exit 1
fi

ACTIVE_ADDRESS="$(sui client active-address 2>/dev/null || echo '<unknown>')"
log "Network       : $NETWORK"
log "Active address: $ACTIVE_ADDRESS"
log "UpgradeCap    : $UPGRADE_CAP_ID"
log "Recipient     : $MULTISIG_ADDRESS"
log "Dry run       : $DRY_RUN"
log ""

if [ "$DRY_RUN" != "0" ]; then
  log "Dry run — would execute:"
  log "  sui client transfer --object-id $UPGRADE_CAP_ID --to $MULTISIG_ADDRESS --gas-budget $GAS_BUDGET"
  log ""
  log "Re-run with DRY_RUN=0 to execute."
  exit 0
fi

read -r -p "Type YES to transfer the UpgradeCap to $MULTISIG_ADDRESS: " CONFIRM
[ "$CONFIRM" = "YES" ] || { log "Aborted."; exit 1; }

sui client transfer --object-id "$UPGRADE_CAP_ID" --to "$MULTISIG_ADDRESS" --gas-budget "$GAS_BUDGET"

log "UpgradeCap transferred to $MULTISIG_ADDRESS. Verify on Sui Explorer and update your custody records."
