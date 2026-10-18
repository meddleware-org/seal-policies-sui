#!/usr/bin/env bash
# Offline tests for scripts/lib.sh, scripts/upgrade.sh and scripts/migrate.sh. A stub `sui` on PATH answers from
# canned JSON, so no network or chain is needed (the real-chain rehearsal is in CUSTODY.md, "Rehearsal").
# Run: bash tests/scripts/ops_scripts_test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT
command -v jq >/dev/null || { echo "jq is required"; exit 1; }

FAILS=0
ok()   { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILS=$((FAILS + 1)); }
eq() { # eq <name> <got> <want>
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1: got '$2', wanted '$3'"; fi
}
expect() { # expect <name> <expected-exit> <stderr-substring> -- cmd...
  local name="$1" want="$2" needle="$3" out rc; shift 4
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" = "$want" ] && [[ "$out" == *"$needle"* ]]; then ok "$name"; else fail "$name (exit $rc, wanted $want, needle '$needle'): $out"; fi
}

MS=0x$(printf 'a%.0s' {1..64})
PKG1=0x$(printf '1%.0s' {1..64}); PKG2=0x$(printf '2%.0s' {1..64})
CFG=0x$(printf 'c%.0s' {1..64}); ADMIN=0x$(printf 'd%.0s' {1..64}); CAP=0x$(printf 'e%.0s' {1..64})

# A checkout in a scratch dir: scripts, a one-line config.move, and the localnet records the publish step writes.
make_repo() {
  local d="$1" src_version="$2" recorded_pkg="$3"
  mkdir -p "$d/scripts" "$d/sources" "$d/bin"
  cp "$SRC"/scripts/lib.sh "$SRC"/scripts/upgrade.sh "$SRC"/scripts/migrate.sh "$d/scripts/"
  printf 'const VERSION: u64 = %s; // test\n' "$src_version" > "$d/sources/config.move"
  echo '{}' > "$d/deployments.json"
  printf 'SEAL_POLICIES_POLICY_CONFIG_ID=%s\nSEAL_POLICIES_POLICY_ADMIN_CAP_ID=%s\n' "$CFG" "$ADMIN" > "$d/.env.localnet"
  cat > "$d/Pub.localnet.toml" <<TOML
[[published]]
source = { local = "/somewhere/else/access-gate-sui" }
published-at = "0x9999999999999999999999999999999999999999999999999999999999999999"
upgrade-capability = "0x8888888888888888888888888888888888888888888888888888888888888888"

[[published]]
source = { local = "$d" }
published-at = "$recorded_pkg"
version = 1
upgrade-capability = "$CAP"
TOML
}

# The stub: STUB_CHAIN_VERSION / STUB_CAP_PACKAGE / STUB_DRY_STATUS steer the answers.
write_stub() {
  cat > "$1/bin/sui" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "--version") echo "sui 1.81.0-stub" ;;
  "client active-env") echo localnet ;;
  "client active-address") echo 0x1 ;;
  "client object "*)
    id="$3"
    case "$id" in
      "$STUB_CFG") echo "{\"content\":{\"id\":\"$id\",\"version\":\"$STUB_CHAIN_VERSION\"}}" ;;
      "$STUB_CAP") [ -n "${STUB_CAP_PACKAGE:-}" ] || exit 1
                   echo "{\"owner\":{\"AddressOwner\":\"$STUB_MS\"},\"content\":{\"package\":\"$STUB_CAP_PACKAGE\"}}" ;;
      "$STUB_ADMIN") echo "{\"owner\":{\"AddressOwner\":\"$STUB_MS\"},\"content\":{}}" ;;
      *) echo "{\"content\":{\"Package\":{\"module_map\":{\"config\":1,\"nft_gate\":1,\"timelock\":1,\"sealed_content\":1}}}}" ;;
    esac ;;
  "client ptb "*"--dry-run"*) echo "Dry run completed, execution status: ${STUB_DRY_STATUS:-success}" ;;
  "client ptb "*"--serialize-unsigned-transaction"*) echo "ignored build chatter"; echo "AAABBBCCC+/=" ;;
  *) echo "stub sui: unexpected: $*" >&2; exit 99 ;;
esac
STUB
  chmod +x "$1/bin/sui"
}

run() { # run <repo> <script> [args] with the stub environment
  local d="$1" script="$2"; shift 2
  env PATH="$d/bin:$PATH" NETWORK=localnet MULTISIG_ADDRESS="${RUN_MS-$MS}" PUB_FILE="$d/Pub.localnet.toml" \
    STUB_CFG="$CFG" STUB_CAP="$CAP" STUB_ADMIN="$ADMIN" STUB_MS="$MS" \
    STUB_CHAIN_VERSION="${STUB_CHAIN_VERSION:-1}" STUB_CAP_PACKAGE="${STUB_CAP_PACKAGE-}" STUB_DRY_STATUS="${STUB_DRY_STATUS:-success}" \
    bash "$d/scripts/$script" "$@"
}

# ── lib.sh: the localnet record lookup picks this checkout's [[published]] block ─────────────────────
R1="$WORK/r1"; make_repo "$R1" 2 "$PKG2"; write_stub "$R1"
got="$(NETWORK=localnet PUB_FILE="$R1/Pub.localnet.toml" bash -c "source '$R1/scripts/lib.sh'; published_field published-at")"
eq "published_field(localnet) selects this checkout's block" "$got" "$PKG2"
got="$(NETWORK=localnet PUB_FILE="$R1/Pub.localnet.toml" bash -c "source '$R1/scripts/lib.sh'; published_field upgrade-capability")"
eq "published_field(localnet) upgrade-capability" "$got" "$CAP"
got="$(NETWORK=localnet bash -c "source '$R1/scripts/lib.sh'; deployment_id policyConfigId SEAL_POLICIES_POLICY_CONFIG_ID")"
eq "deployment_id(localnet) reads .env.localnet" "$got" "$CFG"
echo "{\"testnet\":{\"policyConfigId\":\"$CFG\"}}" > "$R1/deployments.json"
got="$(NETWORK=testnet bash -c "source '$R1/scripts/lib.sh'; deployment_id policyConfigId SEAL_POLICIES_POLICY_CONFIG_ID")"
eq "deployment_id(testnet) reads deployments.json" "$got" "$CFG"
printf '[published.testnet]\npublished-at = "%s"\n' "$PKG1" > "$R1/Published.toml"
got="$(NETWORK=testnet bash -c "source '$R1/scripts/lib.sh'; published_field published-at")"
eq "published_field(testnet) reads Published.toml" "$got" "$PKG1"
got="$(bash -c "source '$R1/scripts/lib.sh'; source_version")"
eq "source_version" "$got" "2"

# ── migrate.sh --verify ──────────────────────────────────────────────────────────────────────────────
export STUB_CAP_PACKAGE="$PKG2" STUB_CHAIN_VERSION=2
expect "verify: migrated, recorded package is the latest" 0 "is at version 2 = VERSION" -- run "$R1" migrate.sh --verify
STUB_CHAIN_VERSION=1 expect "verify: refuses before migrate executed" 1 "migrate has not executed" -- run "$R1" migrate.sh --verify
STUB_CAP_PACKAGE="$PKG1" expect "verify: refuses a stale published-at (cap names another package)" 1 "is not the latest version" -- run "$R1" migrate.sh --verify
STUB_CAP_PACKAGE="" expect "verify: a burned cap is a note, not a failure" 0 "was not found (burned?)" -- run "$R1" migrate.sh --verify

# ── migrate.sh (prepare) ─────────────────────────────────────────────────────────────────────────────
STUB_CHAIN_VERSION=1 expect "prepare: writes the unsigned transaction" 0 "migrate 1 -> 2" -- run "$R1" migrate.sh
eq "prepare: file holds the last output line" "$(cat "$R1/migrate.localnet.tx.b64" 2>/dev/null)" "AAABBBCCC+/="
rm -f "$R1"/migrate.localnet.tx.b64*
STUB_CHAIN_VERSION=1 STUB_DRY_STATUS="failure due to MoveAbort(.., 2)" expect "prepare: refuses when the dry run fails" 1 "would fail on-chain" -- run "$R1" migrate.sh
eq "prepare: no file written after a failed dry run" "$(ls "$R1"/migrate.localnet.tx.b64 2>/dev/null)" ""
STUB_CHAIN_VERSION=2 expect "prepare: nothing to migrate" 1 "nothing to migrate" -- run "$R1" migrate.sh
STUB_CHAIN_VERSION=1 STUB_CAP_PACKAGE="$PKG1" expect "prepare: stale published-at" 1 "is not the latest version" -- run "$R1" migrate.sh
RUN_MS=0x12 expect "prepare: MULTISIG_ADDRESS required" 1 "MULTISIG_ADDRESS must be set" -- run "$R1" migrate.sh
expect "unknown argument" 1 "unknown argument" -- run "$R1" migrate.sh --bogus

# ── upgrade.sh refusals (the build itself needs a real CLI: covered by the chain rehearsal) ───────────
STUB_CHAIN_VERSION=2 expect "upgrade: VERSION must exceed the on-chain version" 1 "needs VERSION > 2" -- run "$R1" upgrade.sh
STUB_CHAIN_VERSION=1 STUB_CAP_PACKAGE="$PKG1" expect "upgrade: cap owned by the multisig, build is attempted" 1 "building the upgrade failed" -- run "$R1" upgrade.sh
STUB_CHAIN_VERSION=1 expect "upgrade: failure shows the CLI's stdout diagnostics" 1 "stub sui: unexpected" -- run "$R1" upgrade.sh

echo
if [ "$FAILS" -ne 0 ]; then echo "$FAILS failure(s)"; exit 1; fi
echo "all passed"
