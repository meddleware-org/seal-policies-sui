# Security Audit — `seal-policies-sui`

**Classification:** Internal security review (initial audit — awaiting external review)
**Project:** seal-policies-sui (`seal_policies`)

- What it is: the on-chain half of Sealed Storage.
- Seal `seal_approve*` policies:
  - `nft_gate` — access-gate pass membership;
  - `timelock` — clock-based unlock.
- Non-policy modules:
  - `sealed_content` — a permissionless discovery registry;
  - `config` — the package-wide version gate.
- Also in scope: the publish and custody scripts, and the npm package that ships the source,
  records and on-chain docs.

**Project type:** Move package (+ on-chain operations scripts + npm package)
**Template:**

- AUDIT_TEMPLATE.md (2026-10-08)
- AUDIT_TEMPLATE_SUI.md (2026-09-28)
- AUDIT_TEMPLATE_SEAL.md (2026-09-30)
- AUDIT_TEMPLATE_OPS.md (2026-10-08)
- AUDIT_TEMPLATE_TS.md (2026-10-08) — npm-package rows only; the package ships no TypeScript.
- AUDIT_TEMPLATE_SUI_CLIENT.md (2026-10-08) — applied only to the transactions the scripts build with the
  Sui CLI (`sui client ptb --move-call` in `migrate.sh`, `sui client upgrade` in `upgrade.sh`,
  `sui client transfer`, `0x2::package::make_immutable`) and to the ID trace. The repository has no
  SDK or TypeScript code.
- Not triggered: VUE, WALRUS, AUTH, PROXY, IMG, GO, RUST, WORKERS, SITE, PLATFORM. No lens registered
  for MCP or DB applies.

**Package:** `seal_policies` v0.0.7; edition 2024.

- Framework rev `83f11dc85d5695a57894329b005b78d75f9bb059` (`Move.lock`, testnet).
- `access_gate` is a git dependency pinned to commit `790695489fc4a7055cb31ce455c670af28f8f3c8`
  (access-gate-sui `7906954`). That commit records `access_gate` testnet `0xd7ddaa94…88c9`.

**Deployment status:**

| Network | Package (original-id · published-at) | Version | UpgradeCap | Status |
| --- | --- | --- | --- | --- |
| testnet (current) | `0x0c8f73490b14836e6a7a724fb46b242cb061d04a5f193fd637159997f8a1773d` · same | 1 | `0x41ecc649ec3a013ba4b8862ea9c218b25d69b150e043ebe1286b4577c4c4f574`, **live**, held by the deploy key `0xa991ae11…164864a` | Published 2026-10-09 from `428e61d`'s parent chain (record `428e61d`, release `a03a532`) with toolchain 1.81.0. Version-gated. Links `access_gate` `0xd7ddaa94…88c9` (version 1; read on-chain this pass). |
| testnet | `0x61c4aaa431cc33a41a9db34621e2925fc8eb4e3b3f1d70eaeb8d8c2b73507e42` (superseded) | 1 | `0x12ee376f…5a74`, burned 2026-10-09 (object gone on-chain) | Immutable. Links the superseded `access_gate` `0xa55789…`. |
| testnet | `0x42cc181f…d612` (superseded; v2 published-at `0x8fcf9c…15cb`) | 2 | `0x0ff7fa39…912f`, burned 2026-10-02 | Immutable. Predates version gating. Links `0x1a81ca…`. |
| testnet | `0x9f0563bf…231e` (superseded) | 1 | `0x20de…a1a0`, burned 2026-09-28 | Immutable. Links the pre-policy `0x0bedd0…`. |
| testnet | strays `0x67520f80…88d3`, `0x882fcc68…e8cc` | — | burned 2026-09-28 | Immutable. Each bundles its own `access_gate` copy, so it is unusable with real gates (F8). |
| mainnet | — | — | — | unpublished |

- `PolicyConfig` (testnet, current) is `0xee0403ba15c250223527150d147f29bedfb1ec46bb2282c341be462ff0ad7d1a`
  (`deployments.json`; shared, `version` 1, read on-chain this pass).
- `PolicyAdminCap` (testnet, current) is `0xd1c704e9af2c2ca775d6fba112d74aa2f219e7a1b08ff45a27ffc06c4d0d3174`,
  owned by the deploy key. It is now recorded in the committed `deployments.json` (F19).
- Custody: both caps are with the deploy key. The multisig transfer and the planned burn are the
  pre-mainnet `CUSTODY.md` process (`OPERATOR_TASKS.md` "Mainnet release custody"; OQ3).
- npm `@meddleware/seal-policies-sui` **0.0.7** (published 2026-10-09T12:45Z) has an SLSA v1 provenance
  attestation. Tag `v0.0.7` = `a03a532` = HEAD, so nothing is unreleased (F24). 18 files.
- Consumers: `@meddleware/seal-client` 0.0.19 (exact devDependency `0.0.7`, `src/deployments.ts` generated
  from it); the docs and dev sites (`^0.0.7`).

**Review date:**

- 2026-09-18 — first pass.
- 2026-09-28 — relocated.
- 2026-09-29, 2026-09-30 — updates.
- 2026-10-03 — re-verified.
- **2026-10-09 — re-verified.**

**Reviewer:** Internal review (Move contract reviewer)
**Severity ceiling:** Medium.

- Policies hold no funds. Seal enforces object ownership before policy logic runs.
- But the policies decide confidentiality of every sealed ciphertext.
- Upgrade authority can change who may decrypt existing content.
- A policy-level bypass is a confidentiality breach for a whole gate.
- Realised ceiling at this pass: **Medium** (F16, now MITIGATED: the contract still approves a frozen
  transferable pass; the clients refuse to seal to transferable gates by default).

**Status:** re-verified 2026-10-09. This is the fifth pass. It covers:

- the remediation wave of 2026-10-08 (`652e7b6`) and the republication of 2026-10-09
  (`150e46d`, `428e61d`, `a03a532`, release 0.0.7);
- the SEAL, OPS and TS lenses at their current dates, and the SUI_CLIENT lens (scripts only);
- the current base template.

**SEAL lens front matter:**

- **`@mysten/seal`:** `^1.4.18`. It is a peer dependency of `@meddleware/seal-client` 0.0.19, the only
  encoder and approve-PTB builder for this package.
- **Key-server mode and committee (consumer configuration, `seal-ui/src/config.ts`):**
  - testnet: Mysten's committee behind one aggregator, plus Mysten's two Open-mode servers;
    threshold **2**;
  - mainnet: three keyless Open-mode servers run by independent operators (Overclock, NodeInfra,
    H2O Nodes); threshold **2** (workspace ADR-0002 / D24).
- **`verifyKeyServers`:** defaults to `true` in seal-client, except for aggregator entries.
  **`checkShareConsistency`:** defaults to `true`.
- **Identity namespace:** the package **original-id** (`0x0c8f7349…`).
  - The approve target is the latest **published-at**; these are equal today.
  - Per Seal documentation, the approved package ID is the first published version, so upgrades keep
    the namespace.

**CLI tools:**

- Sui 1.81.0, pinned in `move-ci.yml` (which `npm-publish.yml` now calls) via `suiup@v0.0.14` (the
  installer tarball is sha256-pinned), and the installed `sui` binary is sha256-checked.
- This matches `Published.toml` `toolchain-version = "1.81.0"`.
- The scripts hard-fail on a major.minor mismatch.
- `jq` is required.

**Networks targetable:**

- `publish.sh`: localnet, testnet, mainnet. Mainnet needs `MAINNET_CONFIRM=1` (a skipped run exits 78)
  and `EXPECTED_SIGNER`.
- `transfer-authority.sh`: the same three, with the same guards.
- `make-immutable.sh`, `upgrade.sh`, `migrate.sh`: the same three, with `MAINNET_CONFIRM=1`.
- `multisig-address.sh`: offline.

**Key material used:** the operator's local Sui keystore (the deploy key). The future custody multisig
is not yet configured (`deployments.json` `multisigAddress: null`). No key is stored in CI.

**Location:** `seal-policies-sui/docs/audit/seal-policies-sui-audit.md`.

- This replaces the 2026-10-03 file in place.
- All `F#` / `OQ#` identifiers from earlier passes are preserved; new IDs this pass start at F31 / OQ13.

---

## Executive summary

`seal_policies` is four small modules (306 lines):

- two **policies**: `nft_gate` and `timelock`;
- a **discovery registry** that is not a policy: `sealed_content`;
- a **version gate**: `config`.

**Positive properties verified at HEAD `a03a532` (tag `v0.0.7`) on sui 1.81.0:**

- **Side-effect freedom.** Every `seal_approve*` is a non-public `entry` taking only immutable
  references. It creates, mutates, transfers and emits nothing.
- **Bounded identity parsing.** Identity decoding is byte-exact and length-guarded.
- **Cross-gate isolation.** A pass for gate A cannot approve gate B. This holds on both the
  transferable and soulbound paths.
- **Version gate.** Every entry, including `sealed_content::publish`, calls `config::check_version`
  first. `migrate` only moves forward.
- **Layout parity with the client.** The identity layouts match `@meddleware/seal-client` through the
  shared conformance vector (`seal-client/tests/conformance-vectors.json` holds the same prefixes the
  Move tests assert).
- **Tests.** **41/41 tests pass**, with **100% module coverage**. `sui move build --lint
  --warnings-are-errors` is clean (CI runs it). All `expected_failure` tests that need a location now
  name it; the mutation run of 2026-10-03 was repeated and no test passes on the wrong abort.

**What changed since the last audit (2026-10-03, 37 tests).** Nearly every finding was fixed in code
and released:

- `652e7b6` (2026-10-08): pinned abort locations, frozen-gate, paused and check-order tests, the
  `upgrade.sh` / `migrate.sh` scripts with a `VERSION` check, the publish-time `access_gate` linkage
  check, signer and balance checks, the coupled-release runbook, release gate equals CI, binary
  checksum and `--lint --warnings-are-errors` in CI.
- `c554955`: grouped weekly Dependabot updates.
- `150e46d`, `428e61d`, `a03a532` (2026-10-09): republication as `0x0c8f7349…` linking the new
  `access_gate` `0xd7ddaa94…` (which forbids the pause-blocks-decryption plus freeze combination and
  fixes the pass kind), release 0.0.7. The old `0x61c4aa…` is immutable.

**Findings by disposition (33 findings, 4 of them Positive):** RESOLVED 19, ADJUDICATED 5, MITIGATED 2,
ACCEPTED-RISK 2, DEFERRED 1.

**Findings not fully closed, in order of importance:**

1. **F16 (Medium, MITIGATED) — a frozen transferable pass gives everyone access to a gate's content.**
   - A holder of a transferable `AccessNFT` (`key, store`) can call
     `transfer::public_freeze_object` on it. The pass becomes an immutable object that **any** address
     can pass as `&AccessNFT` in a Seal dry run, and `nft_gate::seal_approve` approves anyone for all
     past and future content sealed to that gate. Soulbound passes (`key` only) are immune.
   - The contract is unchanged on purpose (decision, OQ9): Sealed Storage uses soulbound gates;
     `seal-client` refuses to seal to a transferable gate unless `allowTransferableGates: true`;
     `SECURITY.md` and the overview document the property; the test
     `a_frozen_transferable_pass_still_approves_for_anyone` pins it.
   - What remains: the protection is client-side. Content sealed by another client to a transferable
     gate is exposed to this property, and the live key-server confirmation is still outstanding (C.2).
2. **F31 (Low, DEFERRED)** — the new `upgrade.sh` / `migrate.sh` paths have never been executed on a
   chain; they are rehearsed before the first real upgrade (pre-mainnet gate).
3. **F23 (Info, MITIGATED)** — two or three documentation nits remain.
4. **F32, F33 (Info, ACCEPTED-RISK)** — `make-immutable.sh` has no `EXPECTED_SIGNER` check; the publish
   workflow no longer runs `npm audit` (no dependencies).

**Posture.**

- The contract logic is minimal and well tested.
- Version gating is correctly built, and the upgrade path is now scripted with its checks.
- The custody tooling is disciplined and the publish script verifies linkage.

The remaining work is maintainer or mainnet work:

- executing the decided custody lifecycle (OQ3, `OPERATOR_TASKS.md` "Mainnet release custody");
- live key-server tests (non-owner rejection, frozen-pass outcome, wrong-version refusal after
  `migrate`) and the localnet rehearsal of upgrade plus `migrate` (F31);
- mainnet committee terms (`OPERATOR_TASKS.md` "Mainnet Seal key servers") and the external review.

---

## Threat model / trust boundaries

**Primary trust anchor:** the Seal key-server committee.

- A threshold (2) of servers must each dry-run a `seal_approve*` PTB under the requester's address
  before releasing key shares.
- Input-ownership resolution in that dry run happens before policy logic. It applies to **owned**
  objects only; shared and immutable inputs need no ownership (F16).
- The policies here are the second gate: they decide *which* owned or accessible objects authorise
  which identities.

| Actor holds / proves | Can do | Bounded by |
| --- | --- | --- |
| Valid, non-exhausted pass for gate G (owned) | Decrypt content namespaced to G, repeatedly | `assert_namespaced` + `is_valid_for*` + `assert_has_uses` + pause policy |
| Exhausted (0-use) pass for G | Nothing | `E_EXHAUSTED` |
| Pass for gate A, targeting gate B content | Nothing | namespace or gate check aborts |
| No NFT; names another holder's **owned** NFT | Nothing | Seal input-ownership resolution |
| **Any address, once some holder froze a transferable pass for G** | **Decrypt all of G's content, forever** | seal-client refuses transferable gates by default; soulbound gates are immune; nothing on-chain (F16) |
| Anyone, timelock content | Decrypt once the key server's full-node `Clock` ≥ `unlock_ms` | `timelock::seal_approve`; full-node clock lag (F26) |
| Anyone | `sealed_content::publish` a pointer under any `gate_id` with any label | permissionless by design; grants nothing; strings bounded (F4) |
| Requester + wallet | Sign the SessionKey personal message | seal-client (its own audit) |
| Storage layer (Walrus) | Serve or withhold public ciphertext | AEAD integrity in Seal; availability only |
| `UpgradeCap` holder (deploy key today) | Replace policy logic. Together with `migrate`, can change who may decrypt **every existing ciphertext** of this namespace | nothing on-chain until burned (OQ3, F3 of the lifecycle) |
| `PolicyAdminCap` holder (deploy key today) | `migrate` the shared config forward to an already-published version | forward-only; inert once the latest version is active; required for any upgrade to take effect (F15) |
| `access_gate` gate admin | Pause the gate (blocks decryption only with `pause_blocks_decryption`); freeze the gate | the gate's immutable `GatePolicy`; a pause-blocks-decryption gate cannot be frozen while paused (F21) |
| Key-server operators (≥ t colluding) | Decrypt everything sealed to their committee, regardless of these policies | committee choice (ADR-0002); out of this package's control |
| Key-server operators (> n − t unavailable) | Deny all decryption (fails closed) | liveness only |
| `access_gate` repo maintainer | Move tags | dependency pinned to a commit SHA (F1) |

### Capabilities & shared objects (Move lens)

| Object / type | Minted / created by | Holder / custodian | Authority it confers | Compromise / misuse impact | Immutability / rotation plan |
| --- | --- | --- | --- | --- | --- |
| `UpgradeCap` `0x41ecc649…f574` (testnet) | publish | deploy key `0xa991…864a` | replace every module's code | retroactively de-gate (or re-gate) every ciphertext in the `0x0c8f7349…` namespace | `CUSTODY.md`: transfer to the multisig, verification window, multisig burn on `plannedBurnDate` — **pre-mainnet blocking** (OQ3) |
| `PolicyAdminCap` `0xd1c704e9…3174` (testnet; recorded in `deployments.json`) | `config::init` | deploy key | `config::migrate` | retire the current version early (only to a published newer one); if **lost**, no upgrade can ever take effect (F15) | multisig permanently (`CUSTODY.md`) — **pre-mainnet blocking** |
| `PolicyConfig` `0xee0403ba…7d1a` (shared) | `config::init` | shared, no owner | read by every entry; `version` | — (mutable only via `PolicyAdminCap`; no public constructor, so no forgeable second config) | one per package lineage (survives upgrades) |
| `SealedContent` (shared, per pointer) | `sealed_content::publish` | shared, no admin | none (read-only data) | discovery spam/phishing only (F4) | immutable (no update/delete) |
| `Gate`, `AccessNFT`, `SoulboundAccessNFT` (external, `access_gate` `0xd7ddaa94…`) | access-gate | shared / holders | read via `is_valid_for*`, `uses_remaining*`, `gate_is_paused`, `gate_pause_blocks_decryption` | governed by access-gate (its audit); **`AccessNFT` has `store`, so holders can freeze it (F16)** | access-gate's policy |
| `Clock` `0x6` (external) | system | shared, immutable reference | timestamps for `timelock` | none | n/a |

### Operations matrix (OPS lens)

| Actor / asset | Power | Bounded by |
| --- | --- | --- |
| Operator EOA / keystore (`0xa991…`) | Signs every publish, transfer and direct burn. Holds both caps today (and access-gate's). | Preflight: active env, chain id, CLI major.minor, `MAINNET_CONFIRM`, balance; `EXPECTED_SIGNER` in `publish.sh` and `transfer-authority.sh` (required on mainnet). On-chain type/package/owner verification before transfers and burns (F9). `make-immutable.sh` has no signer pin (F32). |
| Multisig (planned; not configured) | Burn, `migrate`, upgrades | `CUSTODY.md`. `make-immutable.sh`, `upgrade.sh` and `migrate.sh` write unsigned transactions after on-chain checks (F17). |
| CI runner | None. No workflow signs on a chain. | — |
| Env files (`.env.<network>`) | The authority object IDs the transfer script falls back to | git-ignored (`.env.localnet/testnet/mainnet`, `.env.*.bak`); the committed `deployments.json` is now the first record (F19) |
| Operator's global CLI state | Which network and signer a later `sui` command uses | scripts require the active env to equal `NETWORK` and never switch env or address (I25) |
| CLI binaries | What executes | suiup installer sha256-pinned; the Sui binary sha256-checked in CI (F25); local scripts check major.minor |
| Downstream consumers of written IDs | Call targets and the version object | `Published.toml` + `deployments.json` shipped in npm → `@meddleware/seal-client` `src/deployments.ts`, generated and CI-checked (`check:deployments`), currently from `0.0.7` |

### Script inventory (OPS lens)

| Script | Signs? | Objects touched | Irreversible? | Dry-run default | Confirmation | Network guard | Writes IDs to |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `scripts/publish.sh <net> [--replace-published]` | yes | new package, `UpgradeCap`, `PolicyAdminCap`, `PolicyConfig` | creates objects (not destructive) | no (publishing is the action) | none (refuses an existing `Published.toml` entry without `--replace-published`) | env == net; chain id; CLI major.minor; balance; `EXPECTED_SIGNER` (mainnet-required); `MAINNET_CONFIRM=1`; pre- and post-publish `access_gate` linkage checks | `.env.<net>` (backup kept), `deployments.json` (`policyConfigId`, `policyAdminCapId`, `policyAdminCapOwner`, custody), `Published.toml` (by Sui) |
| `scripts/transfer-authority.sh [--include-upgrade-cap]` | yes | `PolicyAdminCap`, optionally `UpgradeCap` | effectively (new owner must sign back) | **yes** (`DRY_RUN=1`) | typed `YES` | same preflight, plus `EXPECTED_SIGNER`; owner re-read after each transfer | `deployments.json` custody and `policyAdminCapOwner` |
| `scripts/make-immutable.sh` | yes (direct) / writes unsigned tx (multisig) | `UpgradeCap` | **yes** | **yes** | typed `YES` (direct); multisig signatures | same preflight (no signer pin, F32) | `deployments.json` custody (current publication only) |
| `scripts/upgrade.sh` | no (writes an unsigned tx) | `UpgradeCap`, `PolicyConfig` (read) | the signed upgrade is permanent | n/a (nothing executes) | the multisig signs | same preflight via `lib.sh`; `VERSION` > on-chain version; cap owned by `MULTISIG_ADDRESS` | `upgrade.<net>.tx.b64` (git-ignored) |
| `scripts/migrate.sh [--verify]` | no (writes an unsigned tx) | `PolicyAdminCap`, `PolicyConfig` | `migrate` is forward-only and permanent | n/a | the multisig signs | same preflight; `VERSION` > on-chain; cap owned by `MULTISIG_ADDRESS` | `migrate.<net>.tx.b64` (git-ignored); `--verify` is read-only |
| `scripts/multisig-address.sh` | no | — | — | n/a | — | offline | stdout |

## Severity scale

Critical / High / Medium / Low / Info / Positive.

## Scope

**In scope (HEAD `a03a532`, 2026-10-09; tag `v0.0.7` = `a03a532`):**

- `sources/{config,nft_gate,timelock,sealed_content}.move`
- `tests/{config,nft_gate,timelock,sealed_content}_tests.move`
- `Move.toml`, `Move.lock`, `Published.toml`, `deployments.json`
- `scripts/{lib,publish,transfer-authority,make-immutable,upgrade,migrate,multisig-address}.sh`
- `package.json`, `package-lock.json`, `.gitignore`
- `.github/workflows/{move-ci,npm-publish}.yml`, `.github/dependabot.yml`
- `README.md`, `SECURITY.md`, `CUSTODY.md`, `CLAUDE.md`
- `docs/onchain/*`
- the npm tarball (0.0.7)

**Cross-repo evidence (read-only):**

- `access-gate-sui/sources/access_gate.move` (`is_valid_for*`, `uses_remaining*`, pause/policy views,
  `new_gate_policy` and `E_POLICY_COMBINATION`, `AccessNFT` abilities);
- `seal-client` `0.0.19`:
  - `src/providers/{nft-gate,timelock}.ts` (approve argument order, `verifyId`);
  - `src/controller.ts`, `src/gate-check.ts` (`allowTransferableGates`);
  - `src/deployments.ts` (generated from 0.0.7);
  - `tests/conformance-vectors.json`, `tests/integration/*`;
- `seal-ui/src/config.ts` (committee and threshold).

**Out of scope:**

- Seal itself and the key-server committee;
- `access-gate-sui` (own audit);
- `@meddleware/seal-client` and `seal-ui` (own audits; this audit cross-references their coupling).

**Environment / commands (2026-10-09):**

| Command | Result |
| --- | --- |
| `sui move test --build-env testnet` (sui 1.81.0-bf0c491c17b8, in the repo; git dependency at `7906954`) | **41 passed / 0 failed** |
| `sui move test --coverage` + `sui move coverage summary` | **100.00%** for each of `config`, `nft_gate`, `sealed_content`, `timelock` |
| `sui move build --build-env testnet --lint --warnings-are-errors` | no warnings |
| `shellcheck -x -P SCRIPTDIR scripts/*.sh` | **not re-run here** (shellcheck is not installed on this machine); CI runs it and `816d6e0` records a clean 0.9 run |
| Mutation (scratch copy): `config::check_version` made to always abort | 31 of 41 tests fail; the ten that pass are the wrong-version tests, the config tests, the conformance test and the `access_gate` abort test. `short_id_aborts`, `approve_with_7_byte_id_aborts` and `approve_with_wrong_namespace_aborts` now **fail** (F20) |
| `sui client object` on testnet: package `0x0c8f7349…` | modules `config`, `nft_gate`, `sealed_content`, `timelock`; no `access_gate` module; linkage maps `0xd7ddaa94…88c9` to version 1 (F18) |
| `sui client object` on testnet: `PolicyConfig`, `UpgradeCap`, `PolicyAdminCap` | `PolicyConfig` shared, version 1; both caps owned by `0xa991ae11…164864a`; old `UpgradeCap` `0x12ee376f…` not found (burned) |
| `npm pack --dry-run` | 18 files; no `docs/audit` |
| `npm view @meddleware/seal-policies-sui` | versions 0.0.3–0.0.7; 0.0.7 with an SLSA v1 provenance attestation, `gitHead` `a03a532` |
| Live key-server decrypt; live frozen-pass probe | **not run** (needs a funded second wallet and a committee round trip; maintainer e2e) |

Scratch copies live outside the repository. The two coverage artefacts created inside the working tree
(`.coverage_map.mvcov`, `traces/`) were removed.

**Seal documentation basis.** The Sui docs `sui-stack/seal/using-seal` and `sui-stack/seal/sui-stack-seal`
were consulted through search summaries on 2026-10-03; they were not re-fetched this pass. They say:

- the approved package ID is the package's **first published version**, so upgrades keep the
  namespace;
- `seal_approve*` should be **non-public `entry`** functions;
- shared objects should be versioned, or a versioned shared global object used;
- `seal_approve*` is evaluated by `dry_run_transaction_block` on the key server's full node, so results
  can differ between nodes while state propagates.

---

## Findings

### F1 — `access_gate` git dependency pinned to a mutable tag

**Severity:** Low   **Disposition:** RESOLVED

- **Issue (first pass):** `rev = "v0.0.1"`. The tag was later moved to a commit that resolves
  `access_gate` elsewhere.
- **Evidence (`434df4d`, carried forward):** SHA pins.
- **Re-verified 2026-10-09:**
  - `Move.toml` pins `790695489fc4a7055cb31ce455c670af28f8f3c8`, and `Move.lock` pins the same commit
    (`150e46d`).
  - That commit (access-gate-sui `7906954`) records `access_gate` `0xd7ddaa94…88c9`, the package the
    new `0x0c8f7349…` links (checked on-chain, F18).

### F2 — Identity-layout coupling to `seal-client/src/bytes.ts`

**Severity:** Low/Info   **Disposition:** RESOLVED (strengthened by F7)

- **Re-verified 2026-10-09:**
  - `seal-client/tests/conformance-vectors.json` still holds `nftGate.expectedPrefixHex = 00…0123` and
    `timelock.expectedPrefixHex = 0000018cc251f400`.
  - These are the literals asserted by `conformance_gate_id_prefix_layout` and
    `conformance_unlock_ms_big_endian_matches_vector` (both pass).
- **Client-side defence:** seal-client's `verifyId` additionally requires exact lengths: 48 bytes for
  nft-gate, 16 for time-lock.

### F3 — Abort codes reused across modules

**Severity:** Low/Info   **Disposition:** ADJUDICATED

- Codes are legal per module:
  - `config` 1–2;
  - `nft_gate` 1–4;
  - `timelock` 1–2;
  - `sealed_content` 1–3.
- Clients must key on `(module, code)`; dev-guide rule 5 says so.
- **Update:** seal-client has no abort-specific handling today, so the rule is unexercised (OQ5).
- The test-precision problem this overlap caused is fixed (F20).

### F4 — `sealed_content::publish` permissionless and unauthenticated

**Severity:** Info   **Disposition:** ADJUDICATED (by design; OQ4 open)

- See B.4. The behaviour is pinned by `publish_is_permissionless_and_unvalidated`.
- **Since 2026-09-30 (D9):**
  - `label` ≤ 256, `blob_id` ≤ 128 and `seal_id` ≤ 256 bytes, with abort codes 1–3 (boundary and
    over-limit tests).
  - seal-client mirrors the limits (`SEALED_CONTENT_LIMITS`).
  - `publish` is version-gated.

### F5 — Namespacing / timelock byte parsing

**Severity:** Positive

- Length guards precede indexing (`nft_gate.move:70`, `timelock.move:26`).
- The u64 is big-endian over exactly 8 bytes, with no overflow at `u64::MAX`.

### F6 — `sealed_content` had no tests

**Severity:** Low   **Disposition:** RESOLVED (`434df4d`). Now 7 tests.

### F7 — Gate-id conformance test was tautological

**Severity:** Low   **Disposition:** RESOLVED (`434df4d`)

Re-verified: property 2 compares `object::id_from_address(@0x123).to_bytes()` with the vector.

### F8 — Package address drift

**Severity:** Low   **Disposition:** RESOLVED

- Re-verified 2026-10-09 that one current package (`0x0c8f7349…`) is recorded everywhere:
  - `Published.toml`;
  - `deployments.json` (`policyConfigId`);
  - README, SECURITY.md, `docs/onchain/*`, the `Move.toml` comment;
  - seal-client `src/deployments.ts` (generated from `@meddleware/seal-policies-sui` 0.0.7).
- `Move.toml` carries no `published-at`.
- The strays and every superseded package are immutable.
- The broken-stray failure class now has a publish-time guard (F18).

### F9 — Custody scripts did not verify which package's `UpgradeCap` they act on

**Severity:** Medium   **Disposition:** RESOLVED (`dd8fe36`; the scripts were since rewritten and
still hold)

Re-verified 2026-10-09:

- **`transfer-authority.sh`** checks, for every object:
  - the exact type (`<original-id>::config::PolicyAdminCap`, `0x2::package::UpgradeCap`);
  - owner == active address;
  - for the UpgradeCap, `content.package` == this package;
  - since `652e7b6`, it also re-reads each object afterwards and refuses to record the handoff unless
    the new owner is the multisig.
- **`make-immutable.sh`** checks:
  - type, package and owner before the burn;
  - that the cap is gone afterwards;
  - and records the burn only for the current publication's cap (`e76a852`).
- **`upgrade.sh` and `migrate.sh`** check that the cap is owned by `MULTISIG_ADDRESS`.
- The post-upgrade package-resolution edge case is closed (F17).

### F10 — Pausing or freezing a gate does not stop decryption

**Severity:** Low   **Disposition:** RESOLVED (configurable per gate — F14)

- Unchanged behaviour.
- "Freezing never affects decryption" is now asserted by a test: `approve_succeeds_after_the_gate_is_frozen`
  (`652e7b6`).
- Freezing a gate while it is paused is closed by `access_gate` (F21).

### F11 — Documentation drift (first pass)

**Severity:** Info   **Disposition:** RESOLVED. Later drift is F23.

### F12 — Membership, not consumption

**Severity:** Info   **Disposition:** ADJUDICATED (OQ2)

- A pass authorises decryption repeatedly, and a released key stays usable.
- Pinned by `approve_single_use_pass_with_uses_left_succeeds_without_consuming`.

### F13 — docs./dev. sites import the on-chain docs only after npm publication

**Severity:** Info   **Disposition:** RESOLVED. 0.0.7 is published, the sites depend on `^0.0.7`, and
import the real pages.

### F14 — Pause blocks decryption when the gate's policy says so

**Severity:** Info (design)   **Disposition:** RESOLVED (`53a0c95`; on-chain in `0x0c8f7349…`)

- `nft_gate::assert_not_paused_if_required` (`nft_gate.move:80`) is called in both entries.
- `E_GATE_PAUSED = 4`.
- Tests:
  - `approve_denied_while_paused_when_policy_blocks_decryption`;
  - `approve_allowed_while_paused_without_policy`;
  - `approve_resumes_after_unpause_when_policy_blocks_decryption`.

### F15 — Version gating (D22): design verified

**Severity:** Info (design; Positive with operational caveats)   **Disposition:** RESOLVED (`e856167`;
caveats closed by `652e7b6`)

**Where:**

- `sources/config.move` (`init` `:40`, `check_version` `:46`, `migrate` `:51`);
- the first statement of every entry (`nft_gate.move:47, :61`; `timelock.move:25`;
  `sealed_content.move:73`).

**Verified:**

- **The gate.** Every entry takes `&PolicyConfig` as its second (or, for `publish`, first) argument
  and calls `config::check_version` first.
  - `check_version` is `public(package)`, so no other package can satisfy or bypass it.
  - `PolicyConfig` has no public constructor (`new_for_testing` is `#[test_only]`), so a caller cannot
    supply a forged config at the right version.
  - `PolicyConfig` has `key` only, so it cannot be wrapped or transferred away.
- **`migrate`.**
  - It is gated by `&PolicyAdminCap`.
  - It is forward-only: `config.version < VERSION`, else `E_NOT_UPGRADE`.
  - It emits `PolicyConfigMigratedEvent`.
  - Calling `migrate` through an old version always aborts.
  - The cap holder can only move to an already-published version, and the cap becomes inert once the
    config names the latest version.
- **Seal fit.**
  - The identity namespace is the original id, so upgrades never require re-sealing.
  - After `migrate`, a PTB naming any older version aborts with `config::E_WRONG_VERSION`, so key
    servers refuse it.
  - This is the "versioned shared global object" pattern the Seal docs recommend for `seal_approve*`.
- **Tests.**
  - Each of the four entries has a wrong-version test that would otherwise succeed (with
    `location = seal_policies::config`).
  - `migrate` is tested forward, at the current version and backwards.

**Operational caveats** (tracked in F17; status 2026-10-09):

1. **Forgotten bump.** `upgrade.sh` now refuses unless `VERSION` in `sources/config.move` is greater
   than the version the on-chain `PolicyConfig` names. `config_tests.move:19` still holds the literal
   `package_version() == 1`.
2. **Window between upgrade and `migrate`.** The two cannot share a transaction. Until `migrate`
   executes, the old version keeps approving and the new one aborts. `CUSTODY.md` says to run
   `migrate` right away, `migrate.sh` prepares it, and `migrate.sh --verify` checks the result; clients
   switch `publishedAt` only after it.
3. **Losing the `PolicyAdminCap`** means no upgrade can ever take effect. Its ID and holder are now
   committed in `deployments.json` (F19); the remedy for a loss is still a fresh republish (a new
   namespace).

### F16 — A holder can freeze a transferable pass, making the gate's content decryptable by anyone, forever

**Severity:** Medium   **Disposition:** MITIGATED (decision recorded under OQ9; contract unchanged)

**Where:**

- `nft_gate::seal_approve(id, &PolicyConfig, &Gate, nft: &AccessNFT)` (`nft_gate.move:46`);
- `access_gate::AccessNFT has key, store` (`access-gate-sui/sources/access_gate.move`);
- `SECURITY.md` known properties; `docs/onchain/overview.md`; `docs/onchain/user-guide.md`
  ("Transferable passes").

**Issue:**

- Because `AccessNFT` has `store`, its holder can call `sui::transfer::public_freeze_object(nft)`.
- The pass becomes an **immutable** object. Immutable objects are valid inputs for any sender, so a
  Seal key server's dry run under any requester's address resolves it.
- `seal_approve` cannot tell an owned pass from a frozen one: Move has no ownership introspection.
- It approves, because:
  - `is_valid_for` holds;
  - uses never change on a frozen pass, since it can no longer be consumed.

**Evidence:** the 2026-10-03 scratch test is now a committed test,
`a_frozen_transferable_pass_still_approves_for_anyone` (`652e7b6`): a stranger's `seal_approve`
succeeds on a frozen pass (passes at HEAD).

- The `public_share_object` variant aborts: a shared object must be new.
- Soulbound passes (`key` only) can only be frozen by `access_gate`, which never does so; the module
  comment in `tests/nft_gate_tests.move` records that the compiler is the test.
- Live confirmation against a testnet key server is still pending (C.2).

**Impact:**

- One purchase of one transferable pass can make every ciphertext sealed to that gate decryptable by
  everyone — past content and **all future content**.
- It is irrevocable (a frozen object stays frozen) and requires no ongoing effort by the leaker.
- This is materially worse than the known "a holder can leak plaintext" property (F12): it covers
  future releases automatically and costs one transaction.
- The gate owner's only on-chain response is pausing, and only if the gate was created with
  `pause_blocks_decryption`. Pausing denies every holder, so in practice the owner must abandon the
  gate and re-seal content under a new one.
- It does not affect the nft-gate gateways, which check *owned* objects; a frozen pass is owned by no
  one.

**Remediation / evidence** (decision: OQ9, option (a) plus documentation; options (b) and (c) not taken):

- **Soulbound is the supported configuration for sealed content.**
  - `seal-client` 0.0.18 (2026-10-08): `encrypt` for `nft-gate` (with `accessGateOriginalId` set, which
    reads the gate) refuses a gate that mints transferable passes unless `allowTransferableGates: true`
    (`src/controller.ts`, `src/gate-check.ts`). Current release 0.0.19.
  - `SECURITY.md` ("A transferable pass can be frozen into public access") and
    `docs/onchain/overview.md` state the property and tell operators to use soulbound gates;
    the `nft_gate.move` module comment carries it too.
- **Residual risk.** The refusal is client-side and applies only when the client reads the gate. A
  third-party client, or `allowTransferableGates: true`, can still seal to a transferable gate, and
  the contract then approves a frozen pass. The user guide's "Transferable passes" bullet does not
  mention freezing (F23). No on-chain change is planned: it would need a new soulbound-only policy
  module or an `access_gate` redesign, which the maintainer decided not to take.
- **Tests:** the property is recorded as a test (above); the live key-server confirmation is the
  pre-mainnet item in Section D.

### F17 — Upgrade and `migrate` have no OPS tooling or `VERSION`-bump check; `transfer-authority.sh` mis-resolves the package after an upgrade

**Severity:** Low   **Disposition:** RESOLVED (`652e7b6`; the scripts' first real execution is F31)

**Where (as found 2026-10-03):**

- `CUSTODY.md` "Upgrading during the verification window" (manual `sui client upgrade … --serialize-unsigned-transaction`
  and a hand-built `migrate` call);
- `scripts/transfer-authority.sh:74-75`;
- `config_tests.move:19`.

**Issue (as found):**

- The irreversible path the custody lifecycle exists for — upgrade then `migrate` — had no script.
- The manual steps had none of the OPS-lens safeguards: no preflight, no check that `VERSION` was
  bumped, no linkage check, no post-`migrate` verification, no record update, no consumer-release
  prompt.
- `transfer-authority.sh` preferred `.env.<net>`'s `SEAL_POLICIES_PACKAGE_ID` (the original publish)
  over `Published.toml` `published-at`, so after an upgrade its own check refused the cap.

**Remediation / evidence (`652e7b6`):**

- `scripts/upgrade.sh`: shared preflight (`scripts/lib.sh`); reads `PolicyConfig.version` on-chain and
  refuses unless `VERSION` (parsed from `sources/config.move`) is greater; requires the UpgradeCap to be
  owned by `MULTISIG_ADDRESS`; writes the unsigned upgrade transaction and prints the signing steps.
- `scripts/migrate.sh`: prepares the unsigned `config::migrate` call (cap ownership and version
  checked); `--verify` checks that the `PolicyConfig` names `VERSION`, that the latest package has the
  four expected modules and no bundled `access_gate`, and prints the consumer release steps.
- `transfer-authority.sh` now resolves `PACKAGE_ID` from `Published.toml` first, as `make-immutable.sh`
  does, and reads `PolicyAdminCap` from `deployments.json` first.
- `CUSTODY.md` "Upgrading during the verification window" now uses these scripts.
- Not done (MAY, S6): a CI check comparing the source `VERSION` with the on-chain version on release
  branches, and a test that reads `VERSION` instead of the literal at `config_tests.move:19`.
- Decision recorded under OQ10: scripted, with `migrate` in a separate transaction run immediately.

### F18 — `publish.sh` does not verify the published package's `access_gate` linkage

**Severity:** Low   **Disposition:** RESOLVED (`652e7b6`; exercised by the 2026-10-09 publication)

**Where (as found):** `scripts/publish.sh:100-122`. After publishing it extracted IDs but never
inspected the package's linkage table.

**Issue (as found):** a publish that resolved `access_gate` differently would produce a package whose
`nft_gate` is useless (the strays `0x67520f…` and `0x882fcc…`, F8), noticed only when users fail to
decrypt.

**Remediation / evidence:**

- Before publishing (testnet/mainnet), `publish.sh` reads `access_gate`'s `Published.toml` at the
  commit `Move.toml` pins, requires a publication for the target network, and requires that its
  `published-at` exists on chain.
- After publishing, it reads the new package object and requires the linkage table to map
  `access_gate`'s original id to that `published-at` and the module map to contain no `access_gate` of
  its own; otherwise it exits with "DO NOT USE IT: burn its UpgradeCap" before writing
  `deployments.json`.
- Live evidence, read independently this pass: package `0x0c8f7349…` has modules `config`,
  `nft_gate`, `sealed_content`, `timelock` only, and its linkage table maps `0xd7ddaa94…88c9` to itself
  at version 1.

### F19 — The `PolicyAdminCap` ID and holder are recorded only in git-ignored `.env.<network>`

**Severity:** Low   **Disposition:** RESOLVED (`652e7b6`; signer pin on `make-immutable.sh` is F32)

**Where (as found):**

- `publish.sh:129-134` wrote `SEAL_POLICIES_POLICY_ADMIN_CAP_ID` to `.env.<net>` only;
- `deployments.json` custody recorded no `PolicyAdminCap`;
- no script asserted an expected signer.

**Remediation / evidence:**

- `publish.sh` now writes `policyAdminCapId` and `policyAdminCapOwner` into `deployments.json`;
  `transfer-authority.sh` updates `policyAdminCapOwner` when it hands the cap to the multisig and
  reads the ID from `deployments.json` first.
- Current record: `policyAdminCapId` `0xd1c704e9…3174`, owner `0xa991ae11…164864a`; the on-chain read
  this pass shows the same owner. The UpgradeCap is in `Published.toml` (`upgrade-capability`).
- `EXPECTED_SIGNER` is checked by `publish.sh` and `transfer-authority.sh` (required on mainnet).
  `upgrade.sh` and `migrate.sh` sign nothing. `make-immutable.sh` has no such check (F32).

### F20 — Nine `expected_failure` tests omit `location`; documented properties without tests

**Severity:** Low   **Disposition:** RESOLVED (`652e7b6`)

**Where (as found):** `tests/nft_gate_tests.move` (seven tests) and `tests/timelock_tests.move` (two),
using `#[expected_failure(abort_code = N)]` without `location`.

**Remediation / evidence:**

- All nine now carry `location = seal_policies::nft_gate` / `seal_policies::timelock`. Every
  `expected_failure` in the repository now names its location (the `sealed_content` tests use the
  named constant).
- The mutation run was repeated this pass (`check_version` made to always abort): `short_id_aborts`,
  `approve_with_7_byte_id_aborts` and `approve_with_wrong_namespace_aborts` now fail, as they should.
- New tests: `approve_succeeds_after_the_gate_is_frozen` (frozen gate),
  `paused_policy_gate_with_foreign_pass_aborts_paused_first` (check order),
  `a_blocking_policy_gate_cannot_be_frozen_while_paused` (F21).
- The header comment in `nft_gate_tests.move` lists codes 1–4 and says every test names its location.

### F21 — A paused gate frozen with `pause_blocks_decryption` makes its content permanently undecryptable

**Severity:** Low   **Disposition:** RESOLVED (access-gate-sui policy rule in `0xd7ddaa94…`; pinned here by
`652e7b6`)

**Where (as found):** `nft_gate::assert_not_paused_if_required` together with
`access_gate::make_gate_immutable`.

**Remediation / evidence:**

- `access_gate::new_gate_policy` now aborts `E_POLICY_COMBINATION = 15` unless
  `freeze_requires_unpaused || !(pause_blocks_decryption || pause_blocks_access)`. A gate whose pause
  blocks decryption therefore cannot be frozen while paused (`E_FREEZE_WHILE_PAUSED`), and cannot be
  stuck paused forever. This is the decryption side of access-gate-sui F36.
- Pinned here by `a_blocking_policy_gate_cannot_be_frozen_while_paused` (expects `access_gate` abort 10),
  and the policy gates in the tests are built through `new_gate_policy`.
- The `nft_gate.move` module comment and `docs/onchain/overview.md` state the rule. Gates created on the
  superseded `access_gate` packages are different types and are out of this package's reach.

### F22 — `access_gate` upgrades and republishes need a coupled `seal_policies` release; no runbook

**Severity:** Info   **Disposition:** RESOLVED (`652e7b6`; exercised 2026-10-09)

**Issue (as found):**

- **Upgrades.** An `access_gate` *upgrade* that changes view semantics does not reach `nft_gate` until
  `seal_policies` is itself upgraded with the new linkage; the `access_gate` version gate does not
  cover views.
- **Republishes.** An `access_gate` *republish* makes gates of the new package incompatible types.

**Remediation / evidence:**

- `CUSTODY.md` has a "Coupled releases (`access_gate`)" section covering both cases, and `SECURITY.md`
  lists it as a known property.
- The republish path was run on 2026-10-09: `access_gate` `0xd7ddaa94…` was published, `Move.toml` and
  `Move.lock` were re-pinned to the commit recording it (`150e46d`), `publish.sh` checked the linkage,
  the record was committed (`428e61d`), and 0.0.7 was released (`a03a532`). Content sealed to the old
  gates is unsupported (F27).

### F23 — Documentation drift (this pass)

**Severity:** Info   **Disposition:** MITIGATED (most items corrected; residuals below)

**Corrected (`652e7b6`, `a03a532`):**

- `docs/onchain/api-reference.md` check order: the pause check is listed before `is_valid_for`, with the
  note that a paused policy gate with a foreign pass aborts 4.
- `sources/nft_gate.move` comment: now names `create_gate` / `create_free_gate`, the check order and the
  freeze property.
- `tests/nft_gate_tests.move` header: lists codes 1–4.
- `SECURITY.md` "Scope" now lists `config.move`, and the custody scripts are named as covered by
  `CUSTODY.md`.
- `docs/onchain/overview.md`: the superseded namespaces are declared unsupported (F27).
- `npm-publish.yml`: the `verify` job calls `move-ci.yml`; the comments describe it.

**Residual (Info, docs only):**

- `SECURITY.md` "Scope" still names the superseded `0x61c4aa…` and `0x42cc18…` as covered "while content
  sealed under it is in use", which contradicts the decision that superseded namespaces are unsupported.
- `tests/nft_gate_tests.move:369` still says "see audit OQ" (OQ7 was decided 2026-09-28).
- The user guide's "Transferable passes" bullet and the dev guide do not mention that a holder can
  freeze a pass (SECURITY.md, the overview and the module comment do).
- The README runbook table lists four scripts; `upgrade.sh` and `migrate.sh` are documented in
  `CUSTODY.md` and `CLAUDE.md` only.

**Remediation / evidence:** fix the residual lines at the next documentation touch; none affects behaviour.

### F24 — npm 0.0.6 ships the stale audit and pre-HEAD docs

**Severity:** Info   **Disposition:** RESOLVED (`652e7b6`, `a03a532`; release 0.0.7)

**Issue (as found):** `files` included `docs/`, so the tarball carried the stale audit; tag `v0.0.6`
predated two commits.

**Remediation / evidence:**

- `package.json` `files` now lists `docs/onchain/` instead of `docs/`: the tarball (18 files, checked by
  `npm pack --dry-run`) contains no audit. Decision (OQ12): the repo-local audit is canonical and is not
  shipped.
- 0.0.7 was released from `a03a532` = HEAD (tag `v0.0.7`), so the dev-guide `verifyId` rule
  (`0726070`) and all later docs are on npm. The 0.0.7 provenance attestation is present.

### F25 — CI details

**Severity:** Info   **Disposition:** RESOLVED (`652e7b6`; coverage gate not added — accepted)

- The Sui binary is now sha256-checked after `suiup install` in `move-ci.yml`
  (`c86c0481…`), in addition to the sha256-pinned installer.
- `npm-publish.yml` no longer runs `--if-present` scripts: its `verify` job calls `move-ci.yml`
  (`workflow_call`), so the release runs the Move build, tests and shellcheck.
- `sui move build --build-env testnet --lint --warnings-are-errors` is a CI step.
- No coverage gate: coverage is 100% today and the figure is re-measured at each audit
  (ACCEPTED-RISK, Info). The missing `npm audit` step in the publish workflow is F33.

### F26 — Timelock semantics depend on each key server's full-node clock

**Severity:** Info   **Disposition:** ADJUDICATED (documented property)

**Where:** `timelock::seal_approve` (`timelock.move:24-34`).

**Issue:**

- Each key server dry-runs against its own full node's view of `Clock` `0x6`.
- Per the Seal docs, results can differ across nodes while state propagates, so unlock is approximate
  (seconds) and servers may briefly disagree around the instant.
- There is no upper bound on `unlock_ms`: a far-future value seals content permanently. The user guide
  warns about this ("Choose the time carefully").
- Any suffix after 8 bytes is ignored, by design (nonce).

**Remediation / evidence:**

- None on-chain. `SECURITY.md` now lists the property under "Known, intentional properties".
- Optionally, clients could warn when `unlock_ms` is more than N years ahead.

### F27 — Content sealed under superseded packages: documented as decryptable, unsupported by clients

**Severity:** Info   **Disposition:** ADJUDICATED (decision: legacy namespaces unsupported; OQ11)

**Issue (as found):**

- Each superseded package is its own Seal namespace: `0x61c4aa…`, `0x42cc18…` (v1 and v2 `0x8fcf9c…`),
  `0x9f0563…`. They are immutable and ungated, and link superseded `access_gate` packages.
- seal-client knows only the current package, and its decrypt refuses a ciphertext whose header names
  another package; the docs said the old content "still decrypts".
- The old `0x42cc18…` v1 `publish` lacks the D9 bounds. Only `sealed_content` is affected.

**Remediation / evidence:**

- Decision: legacy namespaces are unsupported (pre-v0.2 policy: packages are republished, not
  migrated; re-seal content when the package changes). seal-client 0.0.19 `src/deployments.ts` records
  only `0x0c8f7349…`.
- `docs/onchain/overview.md` and `SECURITY.md` ("Content sealed under a superseded package is
  unsupported") now say so. A leftover scope line in `SECURITY.md` is listed under F23.

### F28 — Positive: side-effect-free, minimal policies with complete coverage

**Severity:** Positive

- Every `seal_approve*` is a **non-public `entry`**, as Seal recommends, with immutable-reference
  parameters only.
- No `TxContext` is used in the policies.
- The modules share nothing but the version gate. Adding a policy is a new module.
- **100%** module coverage. Every abort code has an `expected_failure` test with its location, on both
  NFT variants where applicable.

### F29 — Positive: script safety and record-keeping core

**Severity:** Positive

- **Shared preflight in every signing script:**
  - `set -euo pipefail`;
  - active env == `NETWORK`;
  - chain-id pinned for testnet (`4c78adac`) and mainnet (`35834a8a`);
  - CLI major.minor vs `toolchain-version`;
  - `MAINNET_CONFIRM=1`, with exit 78 when skipped;
  - `publish.sh`: balance ≥ `GAS_BUDGET`, `EXPECTED_SIGNER`.
- **Dry-run defaults** and a typed `YES` before irreversible actions; `upgrade.sh` and `migrate.sh`
  never sign.
- **On-chain checks:** exact-type, package and owner verification before transfers and burns; owner
  re-read after a transfer; proof of burn (the cap is gone); publish-time linkage verification (F18).
- **Publish safeguards:**
  - refuses to overwrite a `Published.toml` entry without `--replace-published` (with a backup);
  - backs up `.env`;
  - `jq`-parsed IDs with exactly-one-match checks by exact type.
- **Multisig path:** writes unsigned transactions; rehearsed on localnet 2026-10-02 (publish, transfer,
  burn; not upgrade or `migrate`, F31).
- **Hygiene:** shellcheck in CI; git-ignored keystores, env files and unsigned-transaction outputs.

### F30 — Positive: release chain

**Severity:** Positive

- Actions SHA-pinned; `permissions: contents: read`; `id-token: write` only on `publish-npm`.
- Tag-gated (`v*`) with a tag == version check. Idempotent publish. npm client pinned (`11.20.0`).
- OIDC `--provenance`, with the 0.0.7 attestation verified.
- Release gate equals CI: the `verify` job calls `move-ci.yml`, so the tagged commit gets the Move
  build with lints as errors, the tests and shellcheck.
- Grouped weekly Dependabot configuration for npm and GitHub Actions (`c554955`).
- `files` whitelist. No dependencies.

### F31 — The `upgrade.sh` / `migrate.sh` paths have never been executed on a chain

**Severity:** Low   **Disposition:** DEFERRED (pre-mainnet gate: "upgrade/`migrate` rehearsal on localnet",
Section D; run before the first real upgrade or burn)

**Where:** `scripts/upgrade.sh`, `scripts/migrate.sh`, `scripts/lib.sh`; `CUSTODY.md` "Rehearsal".

**Issue:**

- The `CUSTODY.md` rehearsal (2026-10-02) covers publish, transfer to a 1-of-2 multisig and the
  multisig burn. It pre-dates `upgrade.sh` and `migrate.sh`.
- The scripts have no automated test, and their `jq` field paths (for example
  `.content.fields.version // .content.version`, `.content.Package.module_map`) were checked against the
  current CLI output only for objects that exist (this pass read the `PolicyConfig` and the package with
  the same `sui client object --json` and the paths resolve), not through a real upgrade.
- `publish.sh` and `transfer-authority.sh` paths were exercised by the 2026-10-09 publication and the
  2026-10-02 rehearsal.

**Impact:** a defect would surface at the moment an upgrade is urgent. The scripts fail closed (they
write nothing the multisig has not signed), so the cost is delay.

**Remediation / evidence:**

- Rehearse on localnet before the first real use: publish, bump `VERSION` in a scratch copy,
  `upgrade.sh`, sign with the 1-of-2 multisig, `migrate.sh`, execute, `migrate.sh --verify`, and a
  wrong-version approve against the old package.
- Tracked with the custody execution in `OPERATOR_TASKS.md` "Mainnet release custody".

### F32 — `make-immutable.sh` has no `EXPECTED_SIGNER` check; `lib.sh` `expect_signer` is unused

**Severity:** Info   **Disposition:** ACCEPTED-RISK

**Where:** `scripts/make-immutable.sh` (own `preflight`), `scripts/lib.sh:53-65`.

**Issue:**

- `publish.sh` and `transfer-authority.sh` pin the active address to `EXPECTED_SIGNER` (required on
  mainnet). `make-immutable.sh` does not, and its direct mode burns as whatever address is active.
- `expect_signer` in `lib.sh` is defined but not called; `publish.sh` and `transfer-authority.sh`
  repeat the logic inline.

**Reason accepted:** the direct burn requires the cap's on-chain owner to equal the active address
(otherwise the script switches to the unsigned multisig mode), shows the package and cap, defaults to a
dry run and needs a typed `YES`. The mainnet burn is the multisig path, which signs with the members'
own keys. Removing the dead helper or calling it is a hygiene change for the next script edit.

### F33 — The publish workflow no longer runs `npm audit`

**Severity:** Info   **Disposition:** ACCEPTED-RISK (the package has no dependencies)

**Where:** `.github/workflows/npm-publish.yml`, `.github/workflows/move-ci.yml`.

**Issue:** until `652e7b6` the `verify` job ran `npm audit --audit-level=high`; the job now calls
`move-ci.yml`, which has no npm steps. TS-M8 asks for the audit gate in CI and in the publish workflow.

**Reason accepted:** `package.json` has no dependencies or devDependencies and the lockfile is 314
bytes, so there is nothing to audit; `npm ci` still runs in the publish job, and Dependabot covers npm.
Re-add the step if a dependency is ever added.

---

## Section A — Invariant verification matrix

| # | Invariant | Enforced / asserted at | Proven by | Status |
| --- | --- | --- | --- | --- |
| I1 | **Side-effect freedom:** every `seal_approve*` takes only immutable references and creates, transfers, mutates and emits nothing; non-public `entry` | `nft_gate.move:46-67`, `timelock.move:24-34` | signature and body inspection; lint clean | HOLDS (code-only, structural) |
| I2 | `sealed_content::publish` and `config::migrate` are not policies and never on a dry-run path | module docs; no `seal_approve` outside the policy modules | inspection | HOLDS |
| I3 | **Gating / isolation:** a pass for gate A cannot approve gate B | `assert_namespaced`, `is_valid_for*` | `approve_with_foreign_nft_aborts`, `approve_soulbound_with_foreign_nft_aborts`, `approve_with_wrong_namespace_aborts` (all with `location`; mutation-checked, F20) | HOLDS |
| I4 | **Identity layout:** prefix = 32-byte gate id, byte-exact, length-guarded | `assert_namespaced` | `conformance_gate_id_prefix_layout`, `approve_with_exact_32_byte_id_succeeds`, `approve_with_7_byte_id_aborts` | HOLDS |
| I5 | Exhausted pass rejected (both variants) | `assert_has_uses` | `approve_with_exhausted_pass_aborts`, `approve_soulbound_with_exhausted_pass_aborts` | HOLDS |
| I6 | Unlimited pass always admitted; approval never consumes | `assert_has_uses` | `approve_unlimited_pass_succeeds`, `approve_single_use_pass_with_uses_left_succeeds_without_consuming` | HOLDS |
| I7 | **Timelock:** big-endian u64; never before unlock (per the evaluating node's clock) | `timelock::seal_approve` | `before_unlock_aborts`, `after_unlock_succeeds`, conformance vector, `0` / `u64::MAX` / exact 8 bytes | HOLDS (F26 caveat) |
| I8 | Malformed identity aborts, never reads out of bounds | length guards | `short_id_aborts`, `approve_with_7_byte_id_aborts` | HOLDS |
| I9 | Client and Move layouts match bit-for-bit | shared vector | both repos' conformance tests (re-checked 2026-10-09) | HOLDS |
| I9b | Pause denies decryption only for gates whose immutable policy opts in; unpause restores it; such a gate cannot be frozen while paused | `assert_not_paused_if_required`; `access_gate::new_gate_policy` | F14 tests; `a_blocking_policy_gate_cannot_be_frozen_while_paused`; `paused_policy_gate_with_foreign_pass_aborts_paused_first` (check order) | HOLDS (F21 resolved) |
| I10 | **Abort codes:** unique within each module; map published | `E_*` constants | every code has an `expected_failure` test with its location; `docs/onchain/api-reference.md` | HOLDS |
| I11 | Policy semantics fixed for existing ciphertexts | `UpgradeCap` burned | testnet cap live (custody lifecycle, OQ3) | GAP (pre-mainnet, maintainer; process decided) |
| I12 | **Arithmetic** | timelock shift over 8 bytes only | `unlock_ms_max_with_max_clock_succeeds` | HOLDS |
| I13 | **Version gating:** every entry aborts unless `PolicyConfig.version == VERSION`; `migrate` cap-gated and forward-only; no forgeable config | `config.move`, first line of each entry | four wrong-version tests; three `migrate` tests; `upgrade.sh` requires `VERSION` > on-chain | HOLDS (scripts not yet run on a chain, F31) |
| I14 | **Only the pass owner can authorise** (Seal input ownership) | Seal dry-run ownership resolution | `a_frozen_transferable_pass_still_approves_for_anyone` records the exception | HOLDS for soulbound passes; transferable passes MITIGATED (F16: client refusal, documented) |
| I15 | **Encryption binding:** encrypt under the original id; approve at the latest published-at; `PolicyConfig` passed | seal-client `deployments.ts` (generated from this package) | seal-client provider tests; `deployments` drift check; ABI-drift integration test | HOLDS (consumer-side) |
| I16 | **Capability binding / custody** | `PolicyAdminCap` gates `migrate`; caps to the multisig | `config_tests`; scripts verify type, package and owner; cap IDs recorded in `deployments.json` | HOLDS in code; custody execution pending (OQ3, maintainer) |
| I17 | **Funds** | — | no coins handled | N/A |
| I18 | **Preflight (OPS):** env, chain identifier, CLI major.minor, balance, signer and mainnet guard are hard failures | `lib.sh` `preflight`; `publish.sh`; `transfer-authority.sh`; `make-immutable.sh` | code inspection; `publish.sh` and `transfer-authority.sh` run on testnet / localnet | HOLDS (signer pin missing on `make-immutable.sh`, F32) |
| I19 | **Irreversible operations (OPS):** dry-run by default, separate typed confirmation, mainnet double guard, skipped run exits non-zero | `transfer-authority.sh`, `make-immutable.sh`; `upgrade.sh` / `migrate.sh` only write unsigned transactions | localnet rehearsal 2026-10-02 (transfer, burn) | HOLDS |
| I20 | **Output parsing and partial failure (OPS):** `--json` + `jq`; exactly-one match by exact type; abort on empty IDs; recovery text after each signing step | `publish.sh`, `transfer-authority.sh` | code inspection; 2026-10-09 publication | HOLDS |
| I21 | **Record-keeping (OPS):** original-id and published-at recorded after a publish, consumers bumped, git dependency re-pinned | `Published.toml`, `deployments.json`, `Move.toml`/`Move.lock`; runbook in `CUSTODY.md` / README | 2026-10-09 republication (`150e46d`, `428e61d`, `a03a532`); seal-client `deployments.ts` | HOLDS |
| I22 | **Destructive file operations (OPS):** scripts delete only their own temporary output | `rm -f` of `*.raw` files in `upgrade.sh` / `migrate.sh`; `publish.sh` moves backups | code inspection | HOLDS (code-only) |
| I23 | **Tool-version pins (OPS):** one version in CI, preflight and `Published.toml` | `move-ci.yml` 1.81.0 + binary sha256; `Published.toml` `toolchain-version` | CI file; preflight | HOLDS |
| I24 | **Idempotency (OPS):** a re-run does not publish or transfer twice | `publish.sh` refuses an existing entry; transfer re-verifies ownership; burn re-read | code inspection | HOLDS (code-only) |
| I25 | **Global-state hygiene (OPS):** scripts do not switch env, address or keystore | all scripts require active env == `NETWORK`; none runs `sui client switch` | code inspection | HOLDS (code-only) |
| I26 | **Key custody (OPS):** no keys in CI; mainnet keys never in CI | no workflow signs | workflows | HOLDS; multisig execution pending (OQ3) |
| I27 | **Package-ID semantics (SC):** call targets use published-at; type strings use original-id | `migrate.sh` (`${PACKAGE_ID}::config::migrate`, published-at from `Published.toml`); `verify_object` types use the original id | code inspection | HOLDS (code-only) |
| I28 | **Execution result (SC):** a signing step counts only on a zero exit and an on-chain re-read | `transfer-authority.sh` (owner re-read), `make-immutable.sh` (cap gone), `migrate.sh --verify` | code inspection | HOLDS (code-only) |
| I29 | **npm package contents (TS):** whitelisted files, no install-time code, no secrets | `package.json` `files`, no lifecycle scripts | `npm pack --dry-run` (18 files) | HOLDS |

---

## Section B — Supply-chain, publish-authority & capability matrix

### B.1 Dependency, liveness & coupling

| Dependency | Exact object ID / rev / commit | Fails open or closed if unavailable? | Paths it can block | Notes |
| --- | --- | --- | --- | --- |
| `access_gate` (git) | commit `790695489fc4…` → package `0xd7ddaa94…88c9` v1 | n/a (build); on-chain view calls only | `nft_gate` approvals | SHA-pinned (F1); coupled releases documented (F22); linkage verified at publish (F18) |
| Sui framework / MoveStdlib | `83f11dc85d5695a57894329b005b78d75f9bb059` (`Move.lock`) | n/a | build | — |
| System `Clock` `0x6` | `0x6` | n/a | timelock approval | per-node view (F26) |
| Seal key-server committee | testnet: Mysten committee (aggregator) + 2 Mysten Open servers, t = 2; mainnet: Overclock, NodeInfra, H2O Nodes, t = 2 | **closed** — no key shares, no decryption | decrypt | third-party liveness and confidentiality (≥ t collusion) |
| Sui CLI | 1.81.0 via `suiup` v0.0.14 (sha256-pinned installer); binary sha256-checked in CI | n/a | build, test, scripts | local scripts check major.minor only |
| npm | none (no dependencies; 314-byte lockfile) | n/a | — | — |

**Wire / identity-format coupling:**

| Format | Exact layout | On-chain decoder | Off-chain encoder | Conformance vector |
| --- | --- | --- | --- | --- |
| nft-gate identity | `[32-byte gate id][16-byte nonce]` (decoder accepts ≥ 32) | `nft_gate::assert_namespaced` | `seal-client/src/bytes.ts` + `verifyId` (exactly 48) | gate `0x123` → `00…0123` ↔ `conformance_gate_id_prefix_layout` |
| timelock identity | `[8-byte BE unlock_ms][8-byte nonce]` (decoder accepts ≥ 8) | `timelock::seal_approve` | `seal-client/src/bytes.ts` + `verifyId` (exactly 16) | `1704067200000` → `0000018cc251f400` ↔ `conformance_unlock_ms_big_endian_matches_vector` |
| approve PTB | `(id, PolicyConfig, Gate, NFT)` / `(id, PolicyConfig, Clock)` | entry signatures | seal-client `buildApprove` | argument order checked by reading both sides 2026-10-03 and by seal-client's ABI-drift integration test (`tests/integration/abi-drift.integration.test.ts`, env-gated) |
| discovery pointer | `publish(PolicyConfig, gate_id, blob_id, seal_id, label)`; `SealedContentPublished {content_id, gate_id, blob_id, seal_id, label, publisher}` | `sealed_content` | seal-client `buildPublishSealedContentTransaction` (limits mirrored) / BCS parser | field set asserted by `publish_shares_pointer_and_emits_event` |

### B.2 Publish authority, capabilities & secret custody

| Authority / capability / secret | Where minted / held | Custody | Gates | Rotation plan |
| --- | --- | --- | --- | --- |
| npm publish `@meddleware/seal-policies-sui` | `npm-publish.yml` (tag `v*`) | GitHub OIDC → npm trusted publisher; `--provenance` | source, records, docs releases | n/a (no token) |
| `UpgradeCap` | publish | deploy key | policy code | B.3 |
| `PolicyAdminCap` | `config::init` | deploy key (ID committed in `deployments.json`) | `migrate` | multisig, permanently (`CUSTODY.md`) |
| Operator keystore | local | operator | all of the above | multisig migration (OQ3) |

#### CI & release integrity

| Item | Holds? | Evidence |
| --- | --- | --- |
| Actions pinned to SHAs | Yes | `actions/checkout@3d3c42e…`, `actions/setup-node@8207627…` |
| Least privilege | Yes | `contents: read`; `id-token: write` only on `publish-npm` |
| OIDC trusted publishing | Yes | 0.0.7 provenance attestation |
| Tag-gated, idempotent publish | Yes | `v*`; tag == version; registry probe + conflict tolerance |
| Release gate equals CI | Yes | `verify` calls `move-ci.yml` (`workflow_call`) |
| Automated dependency updates | Yes (npm, GitHub Actions) | `.github/dependabot.yml`, grouped weekly. The Move git dependency is re-pinned by hand in the coupled-release runbook. |
| Toolchain integrity | Yes | installer sha256-pinned; Sui binary sha256-checked (F25) |
| Container images | N/A | — |
| Secrets never echoed | Yes | none used |
| Real funds manual-only | Yes | no workflow signs on a chain |
| Test-only modes | N/A (`#[test_only]` functions are excluded from the published bytecode by the compiler) | — |

### B.3 `UpgradeCap` custody & immutability policy

| Network | Package ID | `UpgradeCap` ID | Status | Intended policy | Tooling |
| --- | --- | --- | --- | --- | --- |
| testnet | `0x0c8f7349…773d` (current) | `0x41ecc649…f574` | **held** by the deploy key | `CUSTODY.md`: transfer to the multisig (with the `PolicyAdminCap`), verification window, multisig-signed burn on `plannedBurnDate` (maintainer decision 2026-10-01; `plannedBurnDate: null` today). Execution is maintainer work (`OPERATOR_TASKS.md` "Mainnet release custody"). | `transfer-authority.sh` / `make-immutable.sh` (F9, F29); `upgrade.sh` / `migrate.sh` (F17, F31) |
| testnet | `0x61c4aa…7e42` (superseded) | `0x12ee376f…5a74` | **burned** 2026-10-09 (not found on-chain) | — | `make-immutable.sh` with `UPGRADE_CAP_ID`/`PACKAGE_ID` |
| testnet | `0x42cc18…d612` (superseded; v2 `0x8fcf9c…15cb`) | `0x0ff7fa39…912f` | **burned** 2026-10-02 | — | same |
| testnet | `0x9f0563…231e` (superseded) | `0x20de…a1a0` | **burned** 2026-09-28 | — | — |
| testnet | `0x67520f…88d3`, `0x882fcc…e8cc` (strays) | `0xbecf98…c8af`, `0x507dd6d1…0689` | **burned** 2026-09-28 | — | — |
| mainnet | — | — | unpublished | same lifecycle (OQ3) | same scripts |

**SEAL lens — upgradeability governs historical ciphertexts.** The namespace is the original id, so an
upgrade (plus `migrate`) changes the approval logic for **every** ciphertext ever sealed under
`0x0c8f7349…`, not only new ones. That is why the burn is the end state, and why the window between
publish and burn should be short and announced.

### B.4 Permissionless & griefing surfaces

| Function | Attacker controls | Confidentiality | Discoverability / UX | Gas / state | Mitigation |
| --- | --- | --- | --- | --- | --- |
| `sealed_content::publish` | `gate_id` (any, unvalidated), `blob_id` ≤ 128, `seal_id` ≤ 256, `label` ≤ 256; publisher = attacker | **none** (keys still gated) | spam, look-alike labels, pointers to junk or phishing | one shared object per call, paid by the attacker | UI filtering by the gate's `AdminCap` owner or a curated list; dedupe by `seal_id`; optional curated variant (OQ4) |
| `seal_approve*` | identity bytes, object arguments | **frozen transferable pass ⇒ anyone (F16, mitigated)** | — | dry run only, no state | length guards; Seal ownership resolution (owned inputs only); soulbound gates by default in seal-client |
| `public_freeze_object(AccessNFT)` (framework, by any holder) | one pass | **all content of that gate, forever** (F16) | — | one transaction | OQ9 decision: soulbound gates for sealed content |

### B.5 Replay protection & event semantics

No consume or grant happens on-chain here. Approval is a stateless dry run, and Seal returns key shares,
not a one-time token, so replay is **not applicable** (F12).

| Event | Emitted by | Fields | Consumers | Trust |
| --- | --- | --- | --- | --- |
| `SealedContentPublished` | `sealed_content::publish` (before share) | `content_id, gate_id, blob_id, seal_id, label, publisher` | seal-client `listSealedContent` (BCS at the original id; indexer display-only) | `publisher` and `label` are attacker-chosen; never authorisation |
| `PolicyConfigMigratedEvent` | `config::migrate` | `from_version, to_version` | none today (ops monitoring candidate, S5) | authoritative record of version retirement |

### B.SC-1 ID-constant trace (SUI_CLIENT lens, scripts and consumers)

| Location | Network | Value | original-id or published-at | Matches the latest on-chain version |
| --- | --- | --- | --- | --- |
| `Published.toml` | testnet | `0x0c8f7349…773d` | both (equal, version 1) | Y — package object read this pass; no newer version |
| `deployments.json` `policyConfigId` | testnet | `0xee0403ba…7d1a` | shared object | Y — type `0x0c8f7349…::config::PolicyConfig`, version 1 |
| `deployments.json` `policyAdminCapId` / owner | testnet | `0xd1c704e9…3174` / `0xa991ae11…164864a` | object | Y — owner read on-chain |
| `Published.toml` `upgrade-capability` | testnet | `0x41ecc649…f574` | object | Y — owner `0xa991ae11…164864a` |
| `Move.toml` / `Move.lock` `access_gate` rev | testnet | `790695489fc4…` | commit | Y — records `access_gate` `0xd7ddaa94…88c9`, which the package links |
| seal-client `src/deployments.ts` (0.0.19) | testnet | `0x0c8f7349…773d` (both) + `policyConfigId` | both | Y — generated from 0.0.7 |
| `Move.toml` comment, README, SECURITY.md, `docs/onchain/*` | testnet | `0x0c8f7349…773d` | prose | Y |

### B.SC-2 Coupling table (scripts)

| Move function | Builder | Test asserting target + arguments |
| --- | --- | --- |
| `config::migrate(&PolicyAdminCap, &mut PolicyConfig)` | `migrate.sh` (`sui client ptb --move-call`) | none (F31); `migrate.sh --verify` checks the result on-chain |
| `0x2::package::make_immutable(UpgradeCap)` | `make-immutable.sh` (`sui client call` / unsigned tx) | localnet rehearsal 2026-10-02 |
| package upgrade | `upgrade.sh` (`sui client upgrade`) | none (F31) |
| object transfer | `transfer-authority.sh` (`sui client transfer`) | localnet rehearsal 2026-10-02; owner re-read |

### B.SEAL-1 Committee readiness (consumer configuration; owned by seal-ui and ADR-0002)

| Network | Servers (operators) | Mode | Threshold | Change process | Effect on existing ciphertexts |
| --- | --- | --- | --- | --- | --- |
| testnet | Mysten committee via `seal-aggregator-testnet.mystenlabs.com` + Mysten Open ×2 | aggregator + independent | 2 | seal-ui env (`VITE_SEAL_*_TESTNET`) | ciphertexts are bound to the servers they were sealed under; re-seal to move (seal-client `describeCiphertext`) |
| mainnet | Overclock, NodeInfra, H2O Nodes (Open, keyless) | independent | 2 | seal-ui env + ADR-0002 | same |

Per the lens: confidentiality beyond a single operator requires t ≥ 2 with independent operators. This
holds on mainnet. On testnet, Mysten operates every server. Mainnet terms are an operator item
(`OPERATOR_TASKS.md` "Mainnet Seal key servers — confirm terms before launch").

### B.SEAL-2 Discovery registries

`sealed_content` pointers are untrusted. seal-client `listSealedContent` pages with a bounded scan, skips
and counts rows that do not decode (`page.skipped`), and the string bounds are mirrored. Rendering is the
UI audits' concern (seal-ui).

### B.OPS-1 Runbook linkage

| Operation | Script | Linked from README / CUSTODY / SECURITY |
| --- | --- | --- |
| Fresh publish | `publish.sh` | README runbook table; CUSTODY step 1 |
| Transfer authority | `transfer-authority.sh` | README; CUSTODY step 2 |
| Burn | `make-immutable.sh` | README; CUSTODY step 5 |
| Multisig address | `multisig-address.sh` | README; CUSTODY "The multisig" |
| Upgrade | `upgrade.sh` | CUSTODY "Upgrading…" step 2 (not in the README table, F23) |
| `migrate` | `migrate.sh [--verify]` | CUSTODY "Upgrading…" steps 3–4 (not in the README table, F23) |
| Coupled `access_gate` release | — (procedure) | CUSTODY "Coupled releases (`access_gate`)"; SECURITY.md |

### B.TS-1/2/3 npm package (TS lens, package rows only)

| Check | Holds? |
| --- | --- |
| `exports` | `./package.json`, `./Published.toml`, `./deployments.json`. The docs sites read `docs/onchain/*` from the package directory, not through `exports`. |
| `files` | `Move.toml`, `Move.lock`, `Published.toml`, `sources/`, `docs/onchain/`, `README.md`, `SECURITY.md`, `LICENSE`, `deployments.json`, `CUSTODY.md`. 18 files, no audit. No tests, scripts or env files. |
| Install-time code | none (no lifecycle scripts) |
| Dependencies | none; lockfile committed; `npm ci` in publish; no `npm audit` step (F33, ACCEPTED-RISK) |
| `engines` | `node ^22.18.0 \|\| >=24.12.0` |
| First-party consumers | `@meddleware/seal-client` (exact `0.0.7` devDependency, generator source); the docs and dev sites (`^0.0.7`) |

---

## Section C — Test-coverage & hermetic/live split

### C.1 Coverage grade — A (41/41 on sui 1.81.0; 100% module coverage)

| Dimension | Assessment |
| --- | --- |
| Happy path | A — approve (unlimited, soulbound, single-use with uses), timelock before/after/at, publish, `migrate`, `init` |
| Error path / abort codes | A — every code in every module, both NFT variants where applicable; every `expected_failure` names its location; mutation-checked |
| Boundary / edge | A — exact 32- and 8-byte identities, a 7-byte identity, `unlock_ms` 0 and `u64::MAX`, string limits ±1, version ±1 |
| Security-relevant | A− — cross-gate isolation, conformance vectors over contract code, version gate on every entry, frozen pass (F16), frozen gate (F10), pause+freeze (F21), check order (F23). **Missing:** the shell scripts have no automated tests (F31) |

**Per module (`sui move coverage summary`):** `config` 100.00, `nft_gate` 100.00, `sealed_content`
100.00, `timelock` 100.00.

**Tests per module (re-counted from the CLI output, 2026-10-09):**

| Module | Tests |
| --- | --- |
| `config_tests` | 4 |
| `nft_gate_tests` | 22 |
| `timelock_tests` | 8 |
| `sealed_content_tests` | 7 |
| **Total** | **41** |

### C.2 Hermetic vs. live paths

| Path | Hermetic unit test? | Deferred to | Tracking |
| --- | --- | --- | --- |
| Policy assertions, layouts, registry, version gate | yes | — | `tests/*` |
| Key server rejects a **non-owned** owned-object NFT (input resolution) | no | live testnet decrypt with a second wallet (seal-client has timelock and ABI-drift live suites, not an nft-gate round trip with negatives) | pre-mainnet gate (maintainer e2e) |
| Key server **accepts a frozen** `AccessNFT` for any requester | no (Move side proven by a committed test) | live testnet: freeze a test pass, request a key from another address | F16 |
| Wrong-version PTB refused by key servers after `migrate` | no | localnet/testnet rehearsal of upgrade + `migrate` | F31 |
| `nft_gate` against the live `0xd7ddaa94…` gates | no | live nft-gate decrypt round trip | pre-mainnet gate (maintainer e2e) |
| Custody scripts | no | localnet rehearsal 2026-10-02 (publish, transfer to a 1-of-2 multisig, multisig burn); upgrade/migrate not yet run | F29, F31 |
| Publish linkage | yes on testnet | exercised by the 2026-10-09 publication; independent on-chain read this pass | F18 |

---

## Section D — Deployment-readiness gates

### pre-localnet

- [x] compiles; 41/41 hermetic tests green against the pinned git dependency; lint clean (warnings are errors in CI)
- [x] side-effect freedom verified for all `seal_approve*`; every abort code tested with its location (F20)
- [x] version gate on every entry, with wrong-version tests (F15)
- [x] `SECURITY.md` present (residual wording F23)
- [x] shellcheck in CI; script inventory complete; every irreversible step dry-run by default with its own typed confirmation (OPS)

### pre-testnet *(the package is on testnet)*

- [x] published `0x0c8f7349…` against `access_gate` `0xd7ddaa94…`; superseded and stray packages immutable
- [x] package ID, `PolicyConfig`, `PolicyAdminCap` and custody recorded consistently in `Published.toml` /
  `deployments.json` / consumers — F8, F19
- [x] dependency pinned to a commit SHA; lockfile committed — F1
- [x] identity-layout conformance vector green on both sides — F2/F7
- [x] custody tooling with dry-run default, confirmation and on-chain verification — F9, F29
- [x] npm package with provenance; docs sites import it — F13, F24
- [x] publish verifies `access_gate` linkage — F18
- [x] upgrade/`migrate` tooling written — F17 (the rehearsal is a pre-mainnet item, F31)
- [x] `original-id` and `published-at` recorded everywhere after a publish (OPS) — F8, B.SC-1
- [x] Dependabot configured; release gate equals CI — F30
- [x] hermetic frozen-pass, frozen-gate, paused and check-order tests — F16, F10, F21

### pre-mainnet

- [ ] **Operator requirement before launch:** the `UpgradeCap` and `PolicyAdminCap` held by the
  multisig, a planned burn date set, then the burn — **blocking**; maintainer item (OQ3, B.3,
  `OPERATOR_TASKS.md` "Mainnet release custody")
- [ ] localnet rehearsal of `upgrade.sh` + `migrate.sh` + `migrate.sh --verify` — F31
- [ ] live key-server tests: non-owned rejection; the frozen-pass outcome (F16); wrong-version refusal
  after `migrate`; a testnet `nft_gate` decrypt against a live `0xd7ddaa94…` gate — maintainer e2e
- [ ] mainnet committee verified, `verifyKeyServers` on, t = 2 of independent operators (B.SEAL-1;
  `OPERATOR_TASKS.md` "Mainnet Seal key servers"; owned by seal-ui/ADR-0002)
- [ ] mainnet publication (`EXPECTED_SIGNER` and `MAINNET_CONFIRM` set) — mainnet-blocked
- [ ] external review — after launch, per `OPERATOR_TASKS.md` "Funding, grants and an external audit"

---

## Cross-project themes

- **Supply chain & release integrity:**
  - framework and one git dependency pinned by SHA, with the lockfile committed;
  - CLI pinned through a checksummed installer and a checksummed binary;
  - OIDC provenance on npm; release gate equals CI; grouped Dependabot;
  - IDs flow to seal-client by a generated, CI-checked module.
- **Wire-format coupling & conformance vectors:**
  - the identity layouts are shared through vectors asserted in both repos (B.1);
  - approve-PTB argument order is coupled to seal-client's providers and checked live by seal-client's
    ABI-drift test.
- **On-chain-truth boundary:**
  - access decisions are made only by these policies as evaluated by Seal; UIs never decide access;
  - discovery pointers are untrusted hints;
  - the client-side soulbound refusal (F16) is a guard, not an authorisation.
- **Deployment readiness:** Section D.
- **Chain-access layering & on-chain ID/ABI coupling (ADR-0001):**
  - this package is the Move source of truth; `@meddleware/seal-client` is its domain client;
  - the IDs are the latest version (original-id = published-at = `0x0c8f7349…`, v1) and are traced from
    `Published.toml` / `deployments.json` through the npm package to `seal-client/src/deployments.ts`
    (B.SC-1);
  - the `access_gate` git dependency is pinned to the commit recording `access_gate`'s latest
    publication (`7906954` → `0xd7ddaa94…`);
  - coupled releases with `access_gate` have a runbook (F22), and linkage is verified at publish (F18).
- **Pre-v0.2 policy:** no compatibility findings are raised. The next release is 0.0.8. Legacy
  namespaces (F27) are unsupported by decision, not a compatibility shim.
- **Shared with access-gate-sui:**
  - F16 depends on `AccessNFT`'s `store` ability;
  - F21 is the decryption side of F36 (resolved by `E_POLICY_COMBINATION`);
  - F19 parallels F40;
  - F24 parallels F43;
  - F25 parallels F44.

---

## Normative requirements (MUST / MUST NOT)

1. Every `seal_approve*` MUST remain a non-public `entry`, free of side effects — holds (I1, F28).
2. Identity decoders MUST be length-guarded and bit-for-bit identical to `seal-client`, with the
   shared vector asserted on both sides — holds (I4, I7, I9).
3. A pass for one gate MUST NOT approve another gate's content — holds (I3).
4. A policy MUST NOT approve a requester who neither owns nor is entitled to the authorising object —
   holds for soulbound passes; for transferable passes it **does not hold on-chain** (I14, F16), and is
   mitigated by the decision that sealed content uses soulbound gates (clients refuse transferable gates
   by default; documented).
5. Every entry MUST take `&PolicyConfig` and call `config::check_version` first, and every upgrade
   that changes approval logic MUST bump `VERSION` and be followed promptly by `migrate` — holds in
   code (I13); `upgrade.sh` enforces the bump and `CUSTODY.md` the prompt `migrate`; the scripts' first
   execution is F31.
6. The `access_gate` dependency MUST be pinned to the commit SHA recording the `access_gate`
   publication this package links against, and a publish MUST verify that linkage — holds (F1, F18).
7. Before mainnet, the `UpgradeCap` MUST be burned or held by the multisig per `CUSTODY.md`, and the
   `PolicyAdminCap` MUST be held by the multisig with its ID recorded — the ID is recorded (F19);
   the multisig transfer is **not yet done** (I11, OQ3; maintainer item).
8. One canonical package ID and `PolicyConfig` MUST be recorded in `Published.toml`,
   `deployments.json` and every consumer — holds (F8, B.SC-1).
9. UIs MUST treat `sealed_content` pointers as untrusted discovery hints — documented (dev guide
   rule 4).

**SEAL lens baseline:**

| Requirement | Holds? | Evidence |
| --- | --- | --- |
| Encrypt under the original id; approve at the latest published-at (SEAL-M1) | yes | I15; seal-client `deployments.ts` |
| Approve PTBs contain only `seal_approve*` calls with the correct object arguments (SEAL-M3) | yes (consumer) | B.1 approve-PTB row |
| Threshold ≥ 2 with independent operators for confidentiality claims (SEAL-M4) | mainnet yes; testnet single operator | B.SEAL-1 |
| `verifyKeyServers` on outside committee mode (SEAL-M4) | yes (seal-client default) | front matter |
| Policy-package upgradeability governs historical ciphertexts; plan executed before mainnet (SEAL-M8) | process decided; not executed (maintainer) | B.3, OQ3 |
| No revocation after key release documented (SEAL-M7) | yes | `SECURITY.md`, user guide (F12) |

**OPS lens baseline:**

| Requirement | Holds? | Evidence |
| --- | --- | --- |
| OPS-M1 preflight hard-fails on env, chain id, signer, CLI version | yes (signer pin missing on `make-immutable.sh`, F32) | I18 |
| OPS-M2 `set -euo pipefail`, shellcheck, git-ignored env files | yes | F29; shellcheck in CI (not re-run locally) |
| OPS-M3 dry-run irreversible operations, separate confirmation, mainnet double guard | yes | I19 |
| OPS-M4 machine output, abort on missing IDs | yes | I20 |
| OPS-M5 IDs and recovery commands after every signing step | yes | I20 |
| OPS-M6 original-id and published-at recorded, consumers bumped, dependency re-pinned | yes | I21 |
| OPS-M7 no mainnet keys in CI | yes | I26 |
| OPS-M8 real-chain jobs manual, protected | n/a: no workflow signs | B.2 |
| OPS-M9 restore or document global CLI state | yes (never switched) | I25 |

**SUI_CLIENT lens baseline (scripts only):**

| Requirement | Holds? | Evidence |
| --- | --- | --- |
| SC-M1 latest published-at for call targets, original id for type strings, traced | yes | I27, B.SC-1 |
| SC-M3 only the effects status is success; finality awaited | yes (exit code plus on-chain re-read) | I28 |
| SC-M9 created objects extracted by exact type | yes | `publish.sh` `created_id` |
| SC-M5, SC-M6, SC-M7, SC-M8, SC-M10 | n/a: no SDK code, no signature verification, no dry-run PTB, no events used for authorisation | — |

**TS lens baseline (package rows only):** TS-M7 holds (whitelisted files, no install-time code, B.TS);
TS-M8 holds apart from the missing `npm audit` step on a package with no dependencies (F33); the other
TS requirements are n/a (no TypeScript).

## Implementation suggestions (SHOULD / MAY)

- **S1** SHOULD add a testnet integration test: seal and decrypt under `nft_gate` against a live gate,
  verify rejection for a non-holder, and record the frozen-pass outcome (F16, C.2).
- **S2** MAY add an `AdminCap`-gated `publish_curated` so a gate operator can mark official pointers
  (OQ4).
- **S3** SHOULD have seal-ui filter pointers by the gate's `AdminCap` owner by default.
- **S4** MAY give each module distinct abort-code ranges in a future version (F3).
- **S5** SHOULD monitor `PolicyConfigMigratedEvent` and `UpgradeCap` / `PolicyAdminCap` ownership
  changes from the treasury/status tooling.
- **S6** SHOULD replace the literal in `config_tests.move:19` with a test that reads `VERSION`
  alongside a comment requiring the bump, and MAY add a CI check comparing the source `VERSION` with the
  on-chain `PolicyConfig.version` on release branches (F17).
- **S7** MAY have seal-client surface `nft_gate` abort 4 and `config` abort 1 distinctly, as the dev
  guide prescribes (OQ5).
- **S8** SHOULD add `upgrade.sh` and `migrate.sh` to the README runbook table, and remove or call the
  unused `expect_signer` helper (F23, F32).

## Open questions (`OQ#`)

1. **OQ1** *(first pass — superseded by F1/F2: SHA pin and shared vector adopted)* Is the SHA-pin rule
   the documented convention for every Move dependency across the org?
   *(2026-10-03: yes in practice — `Move.toml` comment, README, the workspace standing rules.)*
2. **OQ2** *(first pass — intent confirmed: membership, indefinite decryptability)* Should operators be
   offered a policy that bounds decryptions? That would need an on-chain mechanism outside the dry run.
3. **OQ3** Burn or multisig for the `UpgradeCap` — on testnet now, and at mainnet publish?
   - *(2026-09-28, owner: design as if a multisig holds authority — for now a single key. New versions
     with crucial changes stay upgradeable under that authority while being tested; once ready for
     regular users the same authority burns the cap. No burn yet unless the cap goes stale.)*
   - *(2026-09-28, owner: undecided; multisig to be configured later — recorded as an operator
     requirement before launch.)*
   - *(Decided 2026-10-01: the `CUSTODY.md` lifecycle — publish, transfer both caps to the multisig,
     verification window, multisig burn on a planned date. Rehearsed on localnet 2026-10-02. Execution
     pending and maintainer-only: `multisigAddress` and `plannedBurnDate` are `null` on testnet; the
     2026-10-09 caps are with the deploy key — `OPERATOR_TASKS.md` "Mainnet release custody".)*
4. **OQ4** Keep `sealed_content::publish` permissionless for launch, or add a curated variant?
   *(Open. Strings are bounded since D9.)*
5. **OQ5** Will every client disambiguate aborts by `(module, code)? *(Open: seal-client has no abort
   mapping today — S7.)*
6. **OQ6** Which testnet package is canonical? *(2026-09-28: settled by on-chain evidence; superseded
   since by `0x61c4aa…` and then by `0x0c8f7349…`, F8.)*
7. **OQ7** Should pausing or freezing a gate also stop decryption?
   *(2026-09-28, owner: pausing — yes, operator-configurable per gate (F14); freezing — no.)*
8. **OQ8** Burn the stray `UpgradeCap`s?
   *(2026-09-28, owner: yes — burned, with the superseded `0x9f0563…`; `0x42cc18…` burned 2026-10-02;
   `0x61c4aa…` burned 2026-10-09.)*
9. **OQ9** How should Sealed Storage treat transferable passes, given that a holder can freeze
   one into public access (F16)?
   - (a) Soulbound gates only for sealed content, enforced in clients and documented.
   - (b) A new soulbound-only policy module, with `seal_approve` (transferable) retired for new
     content.
   - (c) An `access_gate` design change so content passes cannot be frozen.
   - (d) Accept and document the risk.
   - *(Decided 2026-10: (a) plus (d) for the contract: sealing is soulbound-only in seal-client unless
     `allowTransferableGates` is set; the property is documented and pinned by a test; (b) and (c) not
     taken — see F16.)*
10. **OQ10** Should upgrade and `migrate` be scripted (unsigned-transaction output for the
    multisig, `VERSION` and linkage checks) before the first real upgrade? And should `migrate` be
    executed in the same signing session as the upgrade? (F15, F17)
    - *(Decided 2026-10-08: scripted — `upgrade.sh`, `migrate.sh`; `migrate` is a separate transaction
      run immediately after the upgrade — see F17. Rehearsal: F31.)*
11. **OQ11** Support content sealed under the superseded namespaces (`0x42cc18…`,
    `0x9f0563…`, `0x61c4aa…`) in seal-client, or declare it unsupported and correct the docs and
    `SECURITY.md`? (F27)
    - *(Decided 2026-10: unsupported — see F27.)*
12. **OQ12** *(shared with access-gate-sui)* Should audit files ship in the npm package? If so,
    must each tag carry the current audit? (F24)
    - *(Decided 2026-10: no — the repo-local audit is canonical and `files` no longer includes
      `docs/audit` — see F24.)*

## Risks (residual)

- **Frozen-pass leakage:** a transferable gate sealed to by a client that skips the soulbound check (or
  with `allowTransferableGates`) can still be opened to everyone, irreversibly, by one holder (F16).
- **Key-server liveness and collusion:** decryption needs t = 2 servers (fails closed); ≥ 2 colluding
  operators can decrypt everything sealed to their committee, regardless of these policies.
- **Upgrade authority:** until the burn, one key (later the multisig) can change who may decrypt every
  existing ciphertext in the namespace. A lost `PolicyAdminCap` would make upgrades ineffective (F15).
  Both caps are with a single deploy key today.
- **Untested upgrade path:** `upgrade.sh` / `migrate.sh` have not run on a chain (F31).
- **Indefinite decryptability:** access cannot be revoked once a key is released. A pause under
  `pause_blocks_decryption` stops only new releases.
- **Discovery spoofing:** look-alike pointers; only UI filtering protects users.
- **Cross-repo drift:** identity layouts and approve argument order are duplicated in two repos.
  Vectors and seal-client's ABI-drift test detect drift but do not prevent it.
- **Coupled releases with `access_gate`:** a republish there strands old content here (F22, F27);
  the runbook exists, and the 2026-10-09 republication followed it.

---

## Re-verification log

- 2026-09-18 — first-pass baseline (8 → 12 tests; F1–F5; OQ1–OQ5).
- 2026-09-28 — relocated; re-verified under the then-current template and Sui lens.
  - F1, F6, F7, F11 RESOLVED (`434df4d`); F9 RESOLVED (`dd8fe36`); F8, F10, F12 added. 21/21 tests.
- 2026-09-28 (second pass) — F14 RESOLVED (`53a0c95`); F10 via F14; F8 RESOLVED; OQ3 and OQ7
  answers; OQ8 added. 24/24 tests.
- 2026-09-28 (third pass) — republished as `0x42cc18…` against `0x1a81ca…`; OQ8 answered.
- 2026-09-29 — `Move.lock` pins `dcd2d3c`; 24/24 tests against the git dependency.
- 2026-09-30 — D9 string bounds in `sealed_content::publish` (28/28 tests); custody script preflight;
  README runbook.
- 2026-10-01 / 2026-10-02 — `0x42cc18…` upgraded to v2 (`0x8fcf9c…`, D9). Version gating (D22) and
  republish as `0x61c4aa…` against `access_gate` `0xa55789…` (`e856167`, 0.0.6). `0x42cc18…` cap burned
  (`e76a852` records it). CI pinned to Sui 1.81.0. Custody lifecycle rehearsed on localnet. *(Recorded
  from the repository history; the file was not re-verified at the time.)*
- 2026-10-03 — fourth pass, under AUDIT_TEMPLATE.md (2026-10-02) + SUI + SEAL + OPS + TS
  (package rows), at HEAD `0726070`.
  - **Findings:** the previous file was stale (the version gate was unaudited; header inconsistent).
    F1–F14 re-verified (IDs preserved). New: F15 (version gating, verified), F16 (Medium, frozen
    transferable pass), F17–F21 (Low), F22–F27 (Info), F28–F30 (Positive). OQ9–OQ12 added; the OQ3
    decision of 2026-10-01 recorded.
  - **Measured:** 37/37 tests; 100% coverage per module; lint and shellcheck clean.
  - **Mutation and probe runs:** one mutation run (F20) and one scratch probe (F16), deleted
    afterwards.
  - **Not runnable here:** live chain reads, key-server tests and direct Seal-docs fetches (egress
    blocked).
  - **No findings resolved:** by maintainer instruction that pass only recorded findings.
- **2026-10-09 — fifth pass**, under AUDIT_TEMPLATE.md (2026-10-08) + SUI (2026-09-28) + SEAL
  (2026-09-30) + OPS (2026-10-08) + TS (2026-10-08, package rows) + SUI_CLIENT (2026-10-08, scripts
  only), at HEAD `a03a532` (tag `v0.0.7`).
  - **What changed in the code:** `652e7b6` (2026-10-08) fixed F17–F22, F24 and F25 and added the
    frozen / paused / check-order tests; `c554955` added Dependabot; `150e46d`, `428e61d`, `a03a532`
    republished against `access_gate` `0xd7ddaa94…` (package `0x0c8f7349…`, `PolicyConfig`
    `0xee0403ba…`, caps with the deploy key; the old `0x61c4aa…` cap burned) and released 0.0.7.
  - **Dispositions:** F1, F2, F6–F11, F13–F15 re-verified RESOLVED with updated evidence; F17, F18, F19,
    F20, F21, F22, F24, F25 moved to RESOLVED; F16 and F23 moved to MITIGATED; F27 ADJUDICATED
    (decision: unsupported); F3, F4, F12, F26 unchanged. **New:** F31 (DEFERRED, upgrade/migrate
    rehearsal), F32 and F33 (ACCEPTED-RISK). Final counts (33 findings): RESOLVED 19, ADJUDICATED 5,
    MITIGATED 2, ACCEPTED-RISK 2, DEFERRED 1, Positive 4.
  - **Decisions recorded:** OQ9 (soulbound-only sealing in seal-client), OQ10 (scripted upgrade and
    migrate), OQ11 (legacy namespaces unsupported), OQ12 (audit not shipped; repo-local audit is
    canonical). OQ3, OQ4 and OQ5 remain open.
  - **Lens coverage:** the Template line gains SUI_CLIENT (scripts and ID trace only); Section A gains
    I18–I29, Section B gains B.SC-1/2 and the CI rows for release gate equals CI and Dependabot, and
    the closing structure gains the OPS, SUI_CLIENT and TS baselines.
  - **Measured:** 41/41 tests (config 4, nft_gate 22, timelock 8, sealed_content 7); 100% coverage per
    module; `--lint --warnings-are-errors` clean; mutation run repeated (31 of 41 fail, no wrong-abort
    passes). On-chain reads: package, `PolicyConfig`, both caps, old cap gone. npm 0.0.7: 18 files,
    SLSA v1 provenance.
  - **Not run here:** shellcheck (not installed; CI covers it), live key-server decrypt and the
    frozen-pass probe, and a localnet run of `upgrade.sh` / `migrate.sh` (F31). Seal documentation was
    not re-fetched.

## Pre-save consistency checklist (this pass)

- [x] Section A ↔ findings: GAP row I11 cites OQ3 (maintainer); I14 is HOLDS for soulbound and MITIGATED
  for transferable (F16); caveats cite F10, F21, F23, F26, F31, F32.
- [x] Finding header ↔ body: consistent; "as found" text is labelled and each remediation describes
  what was done.
- [x] Template line: base + SUI + SEAL + OPS + TS + SUI_CLIENT with dates; untriggered lenses named.
- [x] Closing structure in order: Normative / Suggestions / OQ / Risks.
- [x] Open questions: decisions recorded in place, none deleted.
- [x] Section D boxes ↔ dispositions: unticked items name F31, OQ3, the operator tasks or the mainnet gate.
- [x] Executive summary matches the current dispositions and ceiling (Medium, F16 mitigated).
- [x] C.1 counts re-measured 2026-10-09 (41 tests; 100% per module).
- [x] Re-verification log entry added.
