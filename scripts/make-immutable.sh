#!/usr/bin/env bash
# Burn the seal_policies UpgradeCap, making the published package PERMANENTLY IMMUTABLE.
#
# Why: an upgradeable policy package can retroactively change `seal_approve*` and thereby de-gate
# (or re-gate) all previously sealed content. Burning the UpgradeCap removes that authority — the
# published bytecode can never change. This is one of the two supported custody options; the other
# is transferring the UpgradeCap to a multisig (see transfer-upgrade-cap.sh). Pick one per network.
#
# This mirrors access-gate-sui/scripts/publish.sh --make-immutable.
#
# Usage:
#   NETWORK=testnet bash scripts/make-immutable.sh            # dry run (default)
#   NETWORK=testnet DRY_RUN=0 bash scripts/make-immutable.sh  # execute (IRREVERSIBLE)
#
# The UpgradeCap id is read from Published.toml (`upgrade-capability` under [published.<network>]),
# or override with UPGRADE_CAP_ID.

set -euo pipefail

NETWORK="${NETWORK:-testnet}"
DRY_RUN="${DRY_RUN:-1}"
GAS_BUDGET="${GAS_BUDGET:-100000000}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLISHED_TOML="$REPO_ROOT/Published.toml"

log() { printf '%s\n' "$*" >&2; }

# Extract `upgrade-capability` from the [published.<network>] section of Published.toml.
read_upgrade_cap() {
  awk -v section="[published.${NETWORK}]" '
    $0 == section { in_section = 1; next }
    /^\[/         { in_section = 0 }
    in_section && /^[[:space:]]*upgrade-capability[[:space:]]*=/ {
      gsub(/.*=[[:space:]]*"/, ""); gsub(/".*/, ""); print; exit
    }
  ' "$PUBLISHED_TOML"
}

# Extract `published-at` (this package's id) from the same Published.toml section.
read_package_id() {
  awk -v section="[published.${NETWORK}]" '
    $0 == section { in_section = 1; next }
    /^\[/         { in_section = 0 }
    in_section && /^[[:space:]]*published-at[[:space:]]*=/ {
      gsub(/.*=[[:space:]]*"/, ""); gsub(/".*/, ""); print; exit
    }
  ' "$PUBLISHED_TOML"
}

long_addr() { local h="${1#0x}"; printf '0x%064s' "${h,,}" | tr ' ' 0; }

# Refuse to act unless the active env is NETWORK and UPGRADE_CAP_ID is an UpgradeCap for THIS
# package (Published.toml published-at, or PACKAGE_ID override) owned by the active address. The
# same deploy key may hold other packages' UpgradeCaps — never burn/transfer the wrong one.
verify_upgrade_cap() {
  local active_env pkg json typ owner cap_pkg
  active_env="$(sui client active-env 2>/dev/null || true)"
  [ "$active_env" = "$NETWORK" ] || { log "ERROR: active Sui env is '$active_env', expected '$NETWORK'."; exit 1; }
  pkg="${PACKAGE_ID:-$(read_package_id)}"
  [ -n "$pkg" ] || { log "ERROR: cannot determine this package's id (Published.toml published-at or PACKAGE_ID)."; exit 1; }
  json="$(sui client object "$UPGRADE_CAP_ID" --json 2>/dev/null)" || { log "ERROR: UpgradeCap $UPGRADE_CAP_ID not found on $NETWORK (already burned?)."; exit 1; }
  typ="$(jq -r '.objType // empty' <<<"$json")"
  owner="$(jq -r '.owner.AddressOwner // empty' <<<"$json")"
  cap_pkg="$(jq -r '.content.package // empty' <<<"$json")"
  [ "$typ" = "0x0000000000000000000000000000000000000000000000000000000000000002::package::UpgradeCap" ] \
    || { log "ERROR: $UPGRADE_CAP_ID is a '$typ', not an UpgradeCap."; exit 1; }
  [ "$(long_addr "$cap_pkg")" = "$(long_addr "$pkg")" ] \
    || { log "ERROR: UpgradeCap $UPGRADE_CAP_ID controls package $cap_pkg, not seal_policies $pkg."; exit 1; }
  [ "$(long_addr "$owner")" = "$(long_addr "$(sui client active-address)")" ] \
    || { log "ERROR: UpgradeCap $UPGRADE_CAP_ID is owned by '${owner:-<not address-owned>}', not the active address."; exit 1; }
  log "Verified     : UpgradeCap for seal_policies $pkg, owned by the active address"
}

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
  log "       Set UPGRADE_CAP_ID=0x... or check Published.toml [published.$NETWORK].upgrade-capability."
  exit 1
fi

log "Network      : $NETWORK"
log "UpgradeCap   : $UPGRADE_CAP_ID"
log "Dry run      : $DRY_RUN"
verify_upgrade_cap
log ""
log "WARNING: make_immutable is PERMANENTLY IRREVERSIBLE. The seal_policies package can never be"
log "         upgraded again; future changes must ship as a NEW package at a new address, and every"
log "         verifier/committee must be pointed at the new package id."
log ""

if [ "$DRY_RUN" != "0" ]; then
  log "Dry run — would execute:"
  log "  sui client call --gas-budget $GAS_BUDGET \\"
  log "    --package 0x2 --module package --function make_immutable --args $UPGRADE_CAP_ID"
  log ""
  log "Re-run with DRY_RUN=0 to execute."
  exit 0
fi

read -r -p "Type YES to permanently burn the UpgradeCap: " CONFIRM
[ "$CONFIRM" = "YES" ] || { log "Aborted."; exit 1; }

sui client call --json --gas-budget "$GAS_BUDGET" \
  --package 0x2 --module package --function make_immutable \
  --args "$UPGRADE_CAP_ID"

# The UpgradeCap being consumed is the only proof of immutability (a package object is always
# "Immutable"-owned).
if sui client object "$UPGRADE_CAP_ID" --json >/dev/null 2>&1; then
  log "ERROR: UpgradeCap $UPGRADE_CAP_ID still exists after make_immutable."
  exit 1
fi
log "Package is now permanently immutable (UpgradeCap consumed). Remove/annotate the upgrade-capability in Published.toml."
