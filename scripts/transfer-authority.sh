#!/usr/bin/env bash
# Transfer seal_policies authority from the deploy key to the custody multisig (CUSTODY.md step 2).
#
# Objects:
#   - PolicyAdminCap  — authorises config::migrate (always transferred)
#   - UpgradeCap      — only with --include-upgrade-cap; the multisig later burns it on the planned
#                       date with scripts/make-immutable.sh
#
# IDs: POLICY_ADMIN_CAP_ID / UPGRADE_CAP_ID env vars, else the .env.<network> record written by
# publish.sh (the UpgradeCap also falls back to Published.toml `upgrade-capability`).
#
# Safety: every object is re-read on-chain and must have the exact type for THIS package and be owned
# by the active address; anything else aborts before a transfer. DRY_RUN=1 by default; DRY_RUN=0
# executes after a typed "YES". On testnet/mainnet the new owners are recorded in deployments.json.
#
# Usage:
#   NETWORK=testnet MULTISIG_ADDRESS=0x<64hex> bash scripts/transfer-authority.sh [--include-upgrade-cap]
#   DRY_RUN=0 NETWORK=testnet MULTISIG_ADDRESS=0x<64hex> bash scripts/transfer-authority.sh --include-upgrade-cap

set -euo pipefail

NETWORK="${NETWORK:-testnet}"
DRY_RUN="${DRY_RUN:-1}"
GAS_BUDGET="${GAS_BUDGET:-100000000}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLISHED_TOML="$REPO_ROOT/Published.toml"
ENV_FILE="$REPO_ROOT/.env.${NETWORK}"
FW="0x0000000000000000000000000000000000000000000000000000000000000002"

log() { printf '%s\n' "$*" >&2; }

INCLUDE_UPGRADE_CAP=""
for arg in "$@"; do
  case "$arg" in
    --include-upgrade-cap) INCLUDE_UPGRADE_CAP="1" ;;
    *) log "ERROR: unknown argument '$arg'."; exit 1 ;;
  esac
done
MULTISIG_ADDRESS="${MULTISIG_ADDRESS:-}"
[[ "$MULTISIG_ADDRESS" =~ ^0x[0-9a-fA-F]{64}$ ]] || { log "ERROR: MULTISIG_ADDRESS must be set to a 0x-prefixed 64-hex address."; exit 1; }

published_field() {
  awk -v section="[published.${NETWORK}]" -v key="$1" '
    $0 == section { in_section = 1; next }
    /^\[/         { in_section = 0 }
    in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      gsub(/.*=[[:space:]]*"/, ""); gsub(/".*/, ""); print; exit
    }
  ' "$PUBLISHED_TOML" 2>/dev/null || true
}
record() { if [ -f "$ENV_FILE" ]; then sed -n "s/^$1=//p" "$ENV_FILE"; fi; }
long_addr() { local h="${1#0x}"; printf '0x%064s' "${h,,}" | tr ' ' 0; }

# Same preflight as publish.sh / make-immutable.sh.
preflight() {
  local env chain want tool cli
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

PACKAGE_ID="${PACKAGE_ID:-$(record SEAL_POLICIES_PACKAGE_ID)}"
PACKAGE_ID="${PACKAGE_ID:-$(published_field published-at)}"
ORIGINAL_ID="${ORIGINAL_ID:-$(published_field original-id)}"
ORIGINAL_ID="${ORIGINAL_ID:-$PACKAGE_ID}"
POLICY_ADMIN_CAP_ID="${POLICY_ADMIN_CAP_ID:-$(record SEAL_POLICIES_POLICY_ADMIN_CAP_ID)}"
UPGRADE_CAP_ID="${UPGRADE_CAP_ID:-$(record SEAL_POLICIES_UPGRADE_CAP_ID)}"
UPGRADE_CAP_ID="${UPGRADE_CAP_ID:-$(published_field upgrade-capability)}"
[ -n "$PACKAGE_ID" ] || { log "ERROR: cannot determine the seal_policies package id (PACKAGE_ID, .env.$NETWORK or Published.toml)."; exit 1; }
[ -n "$POLICY_ADMIN_CAP_ID" ] || { log "ERROR: POLICY_ADMIN_CAP_ID not set and not in .env.$NETWORK."; exit 1; }

preflight
ACTIVE="$(sui client active-address)"

# verify_object <id> <label> <exact type> [<package the object must control>]
verify_object() {
  local id="$1" label="$2" want="$3" pkg="${4:-}" json typ owner
  json="$(sui client object "$id" --json 2>/dev/null)" || { log "ERROR: $label $id not found on $NETWORK."; exit 1; }
  typ="$(jq -r '.objType // empty' <<<"$json")"
  owner="$(jq -r '.owner.AddressOwner // empty' <<<"$json")"
  [ "$typ" = "$want" ] || { log "ERROR: $id is a '$typ', not $want."; exit 1; }
  [ "$(long_addr "$owner")" = "$(long_addr "$ACTIVE")" ] || { log "ERROR: $label $id is owned by '${owner:-<not address-owned>}', not the active address."; exit 1; }
  if [ -n "$pkg" ]; then
    [ "$(long_addr "$(jq -r '.content.package // empty' <<<"$json")")" = "$(long_addr "$pkg")" ] \
      || { log "ERROR: $label $id does not belong to seal_policies $pkg."; exit 1; }
  fi
  log "Verified     : $label $id"
}

ORIG_LONG="$(long_addr "$ORIGINAL_ID")"
verify_object "$POLICY_ADMIN_CAP_ID" "PolicyAdminCap" "${ORIG_LONG}::config::PolicyAdminCap"
IDS=("$POLICY_ADMIN_CAP_ID"); LABELS=("PolicyAdminCap")
if [ -n "$INCLUDE_UPGRADE_CAP" ]; then
  [ -n "$UPGRADE_CAP_ID" ] || { log "ERROR: no UpgradeCap id (UPGRADE_CAP_ID, .env.$NETWORK or Published.toml)."; exit 1; }
  verify_object "$UPGRADE_CAP_ID" "UpgradeCap" "${FW}::package::UpgradeCap" "$PACKAGE_ID"
  IDS+=("$UPGRADE_CAP_ID"); LABELS+=("UpgradeCap")
  log "NOTE: the package stays upgradeable under multisig control until the multisig burns the"
  log "      UpgradeCap with scripts/make-immutable.sh on the planned date (CUSTODY.md)."
fi

log ""
log "Network      : $NETWORK"
log "From         : $ACTIVE"
log "To           : $MULTISIG_ADDRESS"
for i in "${!IDS[@]}"; do log "  ${LABELS[$i]}  ${IDS[$i]}"; done
if [ "$DRY_RUN" != "0" ]; then
  log ""
  log "Dry run — re-run with DRY_RUN=0 to transfer."
  exit 0
fi
read -r -p "Transfer these objects to $MULTISIG_ADDRESS on $NETWORK? Type YES to confirm: " CONFIRM
[ "$CONFIRM" = "YES" ] || { log "Aborted."; exit 1; }

for i in "${!IDS[@]}"; do
  if ! OUT="$(sui client transfer --object-id "${IDS[$i]}" --to "$MULTISIG_ADDRESS" --gas-budget "$GAS_BUDGET" --json 2>&1)"; then
    log "ERROR: transferring ${LABELS[$i]} failed:"; log "$OUT"
    log "Recovery: the objects before it were sent; re-run with the remaining ones (ownership is re-verified)."
    exit 1
  fi
  log "OK    ${LABELS[$i]} transferred (tx $(jq -r '.digest // "?"' <<<"$(awk '/^{/,0' <<<"$OUT")"))."
done

DEPLOYMENTS="$REPO_ROOT/deployments.json"
if [ "$NETWORK" != "localnet" ] && [ -f "$DEPLOYMENTS" ]; then
  jq --arg n "$NETWORK" --arg ms "$MULTISIG_ADDRESS" --arg cap "$INCLUDE_UPGRADE_CAP" \
    '.[$n].custody.multisigAddress = $ms
     | if $cap == "1" then .[$n].custody.upgradeCapOwner = $ms else . end' \
    "$DEPLOYMENTS" > "$DEPLOYMENTS.tmp" && mv "$DEPLOYMENTS.tmp" "$DEPLOYMENTS"
  log "Recorded the multisig in deployments.json — set custody.plannedBurnDate and commit it."
fi
