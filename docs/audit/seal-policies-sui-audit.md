# Security Audit — `seal-policies-sui`

**Classification:** Internal security review (initial audit — awaiting external review)
**Project:** `repos/seal-policies-sui` — on-chain Seal access-control policies (Sui Move)
**Project type:** Move package
**Template:** AUDIT_TEMPLATE.md (2026-09-28) + AUDIT_TEMPLATE_SUI.md (2026-09-28)
**Package:** `seal_policies` v0.0.3; edition 2024; framework rev `b0535f1f3a33` (Move.lock, testnet); `access_gate` pinned to commit `f191c2d3…`
**Deployment status:** testnet — `0x9f0563bfe42fbd29932cd280cc47efe17f5339b4dc569eb110114665eecc231e` (`Published.toml`; used by `seal-ui` and `seal-client` tests; UpgradeCap `0x20de324f…a1a0` **live**, compatible policy, publisher EOA). A second testnet package `0x67520f80…88d3` exists and is recorded as `published-at` in `Move.toml` and in `seal-ui/.env.example` (F8). Mainnet: unpublished.
**Review date:** 2026-09-18 (first pass) · re-verified and relocated 2026-09-28
**Reviewer:** Internal review (Move contract reviewer)
**Severity ceiling:** Low — policies are read-only `seal_approve*` dry-run gates and hold no capabilities or funds; Seal enforces object ownership before policy logic runs, so a policy is a second gate. The one lever with higher impact is the `UpgradeCap` (an upgrade could de-gate all sealed content) — tracked as a pre-mainnet gate.
**Status:** re-verified 2026-09-28

Relocated from the workspace corpus (`docs/audit/seal-policies-sui-audit.md`, now a pointer stub).
All `F#` / `OQ#` identifiers from the first pass are preserved.

---

## Executive summary

Three small modules: two **policies** (`nft_gate`, `timelock`) and one **registry** that is not a
policy (`sealed_content`). Side-effect-freedom of every `seal_approve*` holds (immutable references
only); identity namespacing is byte-exact with length guards; the identity layouts match
`@meddleware/seal-client` through a shared conformance vector asserted on both sides. **21/21** tests
pass (sui 1.80.0), including the previously untested `sealed_content` and both soulbound abort paths.

This pass fixed, inline:

- **F1 → RESOLVED** — the `access_gate` git dependency was pinned to a *tag*, and that tag **has since
  been moved** to a different commit (whose manifest resolves `access_gate` to a different on-chain
  address). Now pinned to commit `f191c2d…`, exactly what `Move.lock` and the deployed package used.
- **F6** — `sealed_content` had no tests; **F7** — the gate-id conformance test compared a hand-built
  vector with itself; **F9** — the custody scripts would burn or transfer any `UpgradeCap` passed via
  `UPGRADE_CAP_ID`, including another package's (the same key holds access-gate's cap); **F11** doc
  drift.

What remains: burn or multisig the live testnet `UpgradeCap` and do so at mainnet publish (OQ3),
decide which testnet package is canonical (F8, OQ6), and product calls on curated discovery (OQ4)
and whether pausing/freezing a gate should stop decryption (OQ7).

---

## Threat model / trust boundaries

**Primary trust anchor:** the Seal key-server committee, which dry-runs `seal_approve*` under the
requester's address; ownership/input resolution happens before policy logic runs.

| Actor holds / proves | Can do | Bounded by |
| --- | --- | --- |
| Valid, non-exhausted pass for gate G | Decrypt content namespaced to G, repeatedly | `assert_namespaced` + `is_valid_for*` + `assert_has_uses` |
| Exhausted (0-use) pass for G | Nothing | `E_EXHAUSTED` |
| Pass for gate A, targeting gate B content | Nothing | namespace or gate check aborts |
| No NFT, crafts an id referencing another's NFT | Nothing | Seal input-ownership resolution |
| Anyone, timelock content | Decrypt once `Clock ≥ unlock_ms` | `timelock::seal_approve`, system `Clock` |
| Anyone | `sealed_content::publish` a pointer under any `gate_id` | permissionless by design; grants nothing (F4) |
| `UpgradeCap` holder (publisher EOA) | Replace policy logic — could de-gate all sealed content | nothing on-chain today (OQ3) |
| `access_gate` repo maintainer | Move tags | dependency now pinned to a commit SHA (F1) |

### Capabilities & shared objects (Move lens)

| Object / type | Minted / created by | Holder / custodian | Authority it confers | Compromise / misuse impact | Immutability / rotation plan |
| --- | --- | --- | --- | --- | --- |
| `UpgradeCap` (`0x20de…a1a0`, testnet) | publish | publisher EOA `0xa991…864a` | replace `seal_approve*` logic | retroactively de-gate (or re-gate) every sealed ciphertext | burn (`scripts/make-immutable.sh`) or multisig (`scripts/transfer-upgrade-cap.sh`) — pre-mainnet blocking |
| `SealedContent` (shared, per pointer) | `sealed_content::publish` | shared, no admin | none (read-only data) | discovery spam/phishing only | immutable (no update/delete functions) |
| `Gate`, `AccessNFT`, `SoulboundAccessNFT` (external, `access_gate`) | access-gate package `0x0bedd0…` | shared / holders | read via `is_valid_for*`, `uses_remaining*` | governed by access-gate (its own audit) | access-gate's policy |
| `Clock` `0x6` (external) | system | shared, immutable ref | timestamps for `timelock` | none | n/a |
| Package capabilities of its own | — | none (no `init`, no caps) | — | — | — |

## Severity scale

Critical / High / Medium / Low / Info / Positive.

## Scope

- **In scope:** `sources/{nft_gate,timelock,sealed_content}.move`, `tests/*`, `Move.toml`, `Move.lock`,
  `Published.toml`, `scripts/{make-immutable,transfer-upgrade-cap}.sh`, `SECURITY.md`, `README.md`,
  `CLAUDE.md`, `docs/onchain/*`; on-chain state of both testnet packages and the UpgradeCap.
- **Out of scope:** Seal and the key-server committee; `access-gate-sui` (own audit); the client
  encoder `@meddleware/seal-client` (own audit — shares the conformance vector).
- **Environment:** Sui CLI 1.80.0, `sui move test --build-env testnet` → 21/21; testnet gRPC reads of
  `0x9f0563…`, `0x67520f…`, `0x20de…`; custody scripts run in dry-run mode against testnet.

---

## Findings

### F1 — `access_gate` git dependency pinned to a mutable tag
**Severity:** Low   **Disposition:** RESOLVED (was MITIGATED/ADJUDICATED)
**Where:** `Move.toml [dependencies]`.
**Issue:** `rev = "v0.0.1"` (earlier `v0.0.2`). The remote `v0.0.1` tag now points to `e6d63c6`,
whose manifest resolves `access_gate` to `0x692547…`, while `Move.lock` and the deployed package use
`f191c2d` → `0x0bedd0…` (the address of every live gate). Regenerating the lock would have silently
re-linked the policies against a package no gate uses.
**Remediation / evidence:** commit `e45afb6` — `rev = "f191c2d338006c056d4ecfafa9bb0404afed37a5"`;
`Move.lock` unchanged (confirms the SHA is what was already resolved); README/CLAUDE updated to
require SHA pins.

### F2 — Identity-layout coupling to `seal-client/src/bytes.ts`
**Severity:** Low/Info   **Disposition:** RESOLVED (first pass; strengthened by F7)
Shared vector in `seal-client/tests/conformance-vectors.json` ↔ `conformance_*` Move tests.

### F3 — Abort code `1` (and `2`) reused across modules
**Severity:** Low/Info   **Disposition:** ADJUDICATED — legal per module; clients key on
`(module, code)` (documented in `docs/onchain/dev-guide.md`; OQ5).

### F4 — `sealed_content::publish` permissionless and unauthenticated
**Severity:** Info   **Disposition:** ADJUDICATED (by design; OQ4) — see B.4;
`publish_is_permissionless_and_unvalidated` pins the behaviour.

### F5 — Namespacing / timelock byte parsing
**Severity:** Positive — length guards precede indexing; big-endian u64 over exactly 8 bytes.

### F6 — `sealed_content` had no tests
**Severity:** Low   **Disposition:** RESOLVED
**Evidence:** commit `e45afb6` — `tests/sealed_content_tests.move`: shared object created with the
exact fields, one event emitted; permissionless/unvalidated behaviour documented as a test.

### F7 — Gate-id conformance test was tautological
**Severity:** Low   **Disposition:** RESOLVED
**Issue:** "property 2" compared a hand-built `0x123` vector with itself.
**Evidence:** commit `e45afb6` — now asserts `object::id_from_address(@0x123).to_bytes()` (the same
encoding `assert_namespaced` compares via `object::id_bytes`) equals the shared vector.

### F8 — Package address drift
**Severity:** Low   **Disposition:** DEFERRED (OQ6)
**Issue:** `Move.toml published-at = 0x67520f…` and `seal-ui/.env.example` use `0x67520f…`, while
`Published.toml`, `SECURITY.md`, README, `seal-ui`'s default config, `seal-client` integration tests
and the docs site use `0x9f0563…` (the package whose `UpgradeCap` is recorded). Both exist on testnet.
**Remediation:** pick one (OQ6) and align `Move.toml`, `Published.toml` and every consumer.

### F9 — Custody scripts did not verify which package's `UpgradeCap` they act on
**Severity:** Medium   **Disposition:** RESOLVED
**Where:** `scripts/make-immutable.sh`, `scripts/transfer-upgrade-cap.sh`.
**Issue:** with an `UPGRADE_CAP_ID` override (or a stale `Published.toml`), the scripts would burn —
irreversibly — or transfer whatever cap was given; the same deploy key also owns access-gate's
`UpgradeCap`. No active-env or address-format check; no proof of burn.
**Evidence:** commit `e5dbcd5` — both scripts verify on-chain that the object is an `UpgradeCap` whose
`package` equals this package (`Published.toml published-at`), owned by the active address, on the
active env = `NETWORK`; the multisig address is validated; after `make_immutable` the script requires
the cap to be gone. Dry-run against testnet: seal cap verified; access-gate's cap refused.

### F10 — Pausing or freezing a gate does not stop decryption
**Severity:** Low   **Disposition:** ADJUDICATED (documented + tested; OQ7)
`seal_approve*` checks gate membership and uses only, not `paused`/`frozen`;
`approve_on_paused_gate_still_succeeds`.

### F11 — Documentation drift
**Severity:** Info   **Disposition:** RESOLVED — README/CLAUDE said 8 tests and a tag rev; the dev
site documented non-existent modules (`nft_gate_policy::create`, `approve`); now canonical
`docs/onchain/*` consumed by both sites — docs `e311020`, dev `19499e0` (policy guide rewritten).

### F12 — Membership, not consumption
**Severity:** Info   **Disposition:** ADJUDICATED (first-pass OQ2 intent confirmed) — a single-use
pass authorises decryption repeatedly and a released key stays usable;
`approve_single_use_pass_with_uses_left_succeeds_without_consuming` pins it. Documented in
`SECURITY.md` and the user guide.

### F13 — docs./dev. sites import the canonical on-chain docs only after npm publication
**Severity:** Info   **Disposition:** DEFERRED (exact remediation below)
**Where:** `repos/docs` and `repos/dev` — `scripts/gen-onchain.mjs` resolves `@meddleware/seal-policies-sui` from
`node_modules`.
**Issue:** the canonical `docs/onchain/*` pages ship in `@meddleware/seal-policies-sui` from version `0.0.3`. Until
that version is on npm and installed in both sites, their builds render placeholder pages for this
package (by design — builds never fail). Verified locally with `ONCHAIN_DOCS_ROOT=..` (all pages
imported, no dead links, lint/type-check green).
**Remediation:** publish `@meddleware/seal-policies-sui@0.0.3` (push the release tag; `npm-publish.yml`), then in both
`repos/docs` and `repos/dev`: `npm install -D @meddleware/seal-policies-sui@0.0.3` → commit `package.json` +
`package-lock.json` → `npm run build` and confirm the `[gen:onchain]` log shows imported pages
(no placeholder) → release the site images.

---

## Section A — Invariant verification matrix

| # | Invariant | Enforced / asserted at | Proven by | Status |
| --- | --- | --- | --- | --- |
| I1 | **Side-effect-freedom:** every `seal_approve*` takes only immutable references and creates/transfers/mutates/emits nothing | `nft_gate.move::seal_approve*`, `timelock.move::seal_approve` | signature + body inspection | HOLDS (code-only, structural) |
| I2 | `sealed_content::publish` is not a policy and is never on a dry-run path | module docs; no `seal_approve` in `sealed_content` | inspection; `docs/onchain/*` | HOLDS |
| I3 | **Gating / isolation:** pass for gate A cannot approve gate B | `nft_gate::assert_namespaced`, `is_valid_for*` | `approve_with_foreign_nft_aborts`, `approve_soulbound_with_foreign_nft_aborts`, `approve_with_wrong_namespace_aborts` | HOLDS |
| I4 | **Identity layout:** prefix = 32-byte gate id, byte-exact, length-guarded | `nft_gate::assert_namespaced` | `conformance_gate_id_prefix_layout`, `approve_with_exact_32_byte_id_succeeds`, `approve_with_7_byte_id_aborts` | HOLDS |
| I5 | Exhausted pass rejected (both variants) | `nft_gate::assert_has_uses` | `approve_with_exhausted_pass_aborts`, `approve_soulbound_with_exhausted_pass_aborts` | HOLDS |
| I6 | Unlimited pass always admitted; approval never consumes | `nft_gate::assert_has_uses` | `approve_unlimited_pass_succeeds`, `approve_single_use_pass_with_uses_left_succeeds_without_consuming` | HOLDS |
| I7 | **Identity layout:** timelock BE u64, never before unlock | `timelock::seal_approve` | `before_unlock_aborts`, `after_unlock_succeeds`, `conformance_unlock_ms_big_endian_matches_vector`, `unlock_ms_zero_succeeds`, `unlock_ms_max_with_max_clock_succeeds`, `exact_8_byte_id_succeeds` | HOLDS |
| I8 | Malformed identity aborts, never reads out of bounds | length guards | `short_id_aborts`, `approve_with_7_byte_id_aborts` | HOLDS |
| I9 | Client/Move layouts match bit-for-bit | shared vector | both repos' conformance tests | HOLDS |
| I10 | **Abort codes:** unique within each module; map published | `E_*` constants | every code has an `expected_failure` test; map in `docs/onchain/api-reference.md` | HOLDS |
| I11 | Policy semantics fixed for existing ciphertexts | `UpgradeCap` burned | on-chain read: testnet cap live | GAP (OQ3) |
| I12 | **Arithmetic** | timelock shift over 8 bytes only | `unlock_ms_max_with_max_clock_succeeds` | HOLDS |
| I13 | **Ownership / abilities / capability binding / funds** | — | no caps, no funds, no transfers of user objects | N/A |

---

## Section B — Supply-chain, publish-authority & capability matrix

### B.1 Dependency, liveness & coupling

| Dependency | Exact object ID / rev / commit | Fails open or closed if unavailable? | Paths it can block | Notes |
| --- | --- | --- | --- | --- |
| `access_gate` (git) | commit `f191c2d3…` → package `0x0bedd0…` | n/a (build); on-chain reads only | none | own audit; SHA-pinned (F1) |
| Sui framework / MoveStdlib | `b0535f1f3a33…` (Move.lock) | n/a | build | — |
| System `Clock` `0x6` | `0x6` | n/a (always present) | timelock approval | trusted system object |
| Seal key-server committee | committee object IDs (seal-ui config) | **closed** — no key shares, no decryption | decrypt | third-party liveness; nothing is released by default |

**Wire / identity-format coupling**

| Format | Exact layout | On-chain decoder | Off-chain encoder | Conformance vector |
| --- | --- | --- | --- | --- |
| nft-gate identity | `[32-byte gate id][16-byte nonce]` | `nft_gate::assert_namespaced` | `seal-client/src/bytes.ts` | gate `0x123` → `00…0123`; `seal-client/tests/conformance-vectors.json` ↔ `conformance_gate_id_prefix_layout` |
| timelock identity | `[8-byte BE unlock_ms][8-byte nonce]` | `timelock::seal_approve` | `seal-client/src/bytes.ts` | `1704067200000` → `0000018cc251f400` ↔ `conformance_unlock_ms_big_endian_matches_vector` |
| discovery pointer | `SealedContentPublished {content_id, gate_id, blob_id, seal_id, label, publisher}` | `sealed_content::publish` | seal-ui indexer | field set asserted by `publish_shares_pointer_and_emits_event` |

### B.2 Publish authority, capabilities & secret custody

| Authority / capability | Where minted / held | Custody | Gates | Immutability / rotation plan |
| --- | --- | --- | --- | --- |
| npm publish (`@meddleware/seal-policies-sui`) | CI (OIDC) | GitHub OIDC → npm | docs/source releases | n/a |
| `UpgradeCap` | publish | publisher EOA | policy code | B.3 |

### B.3 `UpgradeCap` custody & immutability policy

| Network | Package ID | `UpgradeCap` ID | Status | Intended policy | Tooling |
| --- | --- | --- | --- | --- | --- |
| testnet | `0x9f0563…231e` | `0x20de…a1a0` | **held** by publisher EOA (policy 0) | burn or multisig (OQ3) | `make-immutable.sh` / `transfer-upgrade-cap.sh` (dry-run default, `YES`, on-chain verification — F9) |
| testnet | `0x67520f…88d3` | not recorded | unknown | — | resolve with F8 / OQ6 |
| mainnet | — | — | unpublished | decide before publish (OQ3) | same scripts |

**Versioning:** a new policy version is a new package ID; ciphertexts reference the package in their
approve PTB, so `seal-client` / `seal-ui` must keep supporting every package ID with live content.

### B.4 Permissionless & griefing surfaces

| Function | Attacker controls | Confidentiality | Discoverability / UX | Gas / state | Mitigation |
| --- | --- | --- | --- | --- | --- |
| `sealed_content::publish` | `gate_id` (any, unvalidated), `blob_id`, `seal_id`, `label`; publisher = attacker | **none** (keys still gated by `seal_approve*`) | spam, look-alike labels, pointers to junk/phishing | one shared object per call, paid by attacker | UI: show only pointers whose `publisher` is the gate's operator (AdminCap owner) or a curated list; dedupe by `seal_id`; optional `AdminCap`-gated variant (OQ4) |
| `seal_approve*` | identity bytes | none | — | dry-run only, no state | length guards |

### B.5 Replay protection & event semantics

No consume or grant is performed on-chain here — approval is a stateless dry-run, and Seal returns a
key (not a one-time token). Replay is therefore **not applicable**: a holder may re-request a key
while the pass is valid (F12). Event: `SealedContentPublished` (emitted after object creation, before
share; consumers: seal-ui discovery) — verifiers MUST NOT treat `publisher` or `label` as trusted.

---

## Section C — Test-coverage & hermetic/live split

### C.1 Coverage grade — A− (21/21, sui 1.80.0)

| Dimension | Assessment |
| --- | --- |
| Happy-path | A — approve (unlimited, soulbound, single-use with uses), timelock before/after, publish |
| Error-path / abort codes | A — `nft_gate` 1/2/3 (2 and 3 also soulbound), `timelock` 1/2 |
| Boundary / edge | A — exact 32/8-byte ids, 7-byte id, `unlock_ms` 0 and `u64::MAX`, paused gate |
| Security-relevant | A− — cross-gate on both variants, conformance vectors exercising contract code; live committee rejection not hermetic |

### C.2 Hermetic vs. live paths

| Path | Hermetic unit test? | Deferred to | Tracking |
| --- | --- | --- | --- |
| Policy assertions, layouts, registry | yes | — | `tests/*` |
| Key server rejects a **non-owned** NFT (input resolution) | no | running Seal committee on testnet | pre-mainnet gate |
| Cross-package linkage (policies ↔ live `0x0bedd0…` gates) | no | testnet integration (`seal-client` timelock integration test exists; nft-gate path pending) | pre-mainnet gate |
| Custody scripts | no | testnet dry-run (done 2026-09-28) | F9 |

---

## Section D — Deployment-readiness gates

### pre-localnet

- [x] compiles; 21/21 hermetic tests green — CI `move-ci.yml`
- [x] side-effect-freedom verified for all `seal_approve*`; every abort code tested
- [x] `SECURITY.md` present and consistent with this audit

### pre-testnet

- [ ] docs./dev. sites install the published `@meddleware/seal-policies-sui` and import its on-chain docs — F13
- [x] published — `0x9f0563…` (and `0x67520f…`)
- [ ] package ID recorded consistently across `Move.toml` / `Published.toml` / consumers — F8 (OQ6)
- [x] dependency pinned to a commit SHA; lockfile committed — F1
- [x] identity-layout conformance vector green on both sides — F2/F7
- [x] custody tooling with dry-run default, confirmation and on-chain verification — F9

### pre-mainnet

- [ ] `UpgradeCap` burned or held by a multisig — **blocking** (OQ3)
- [ ] live key-server integration test proving non-owned-NFT rejection
- [ ] testnet integration of `nft_gate` against live `0x0bedd0…` gates
- [x] full Section A coverage except I11; abort-code map published
- [ ] external audit

---

## Cross-project themes

- **Supply chain:** framework + one git dependency pinned by SHA; lockfile committed; the tag
  movement this pass is the concrete case for the SHA rule.
- **Wire-format coupling:** B.1 identity layouts ↔ `seal-client` (SYNTHESIS S3).
- **On-chain-truth boundary:** access decisions are made by on-chain policies evaluated by Seal; UIs
  never decide access.
- **Deployment readiness:** Section D.

## Normative requirements (MUST)

1. `seal_approve*` MUST remain side-effect free — holds (I1).
2. Identity decoders MUST be length-guarded and bit-for-bit identical to `seal-client`, with the
   shared vector asserted on both sides — holds (I4, I7, I9).
3. A pass for one gate MUST NOT approve another gate's content — holds (I3).
4. The `access_gate` dependency MUST be pinned to a commit SHA resolving to the address of the live
   gates — holds (F1).
5. Before mainnet the `UpgradeCap` MUST be burned or held by a multisig — **not yet** (I11, OQ3).
6. One canonical package ID MUST be recorded in `Move.toml`, `Published.toml` and every consumer —
   **not yet** (F8).
7. UIs MUST treat `sealed_content` pointers as untrusted discovery hints — documented (dev guide).

## Implementation suggestions (SHOULD / MAY)

- **S1** SHOULD add a testnet integration test that seals and decrypts under `nft_gate` against a
  live gate, and verifies rejection for a non-holder.
- **S2** MAY add an `AdminCap`-gated `publish_curated` so a gate operator can mark official pointers
  (depends on OQ4).
- **S3** SHOULD have `seal-ui` filter pointers by the gate's `AdminCap` owner by default.
- **S4** MAY give each module distinct abort-code ranges in a future version to simplify clients.

## Open questions (`OQ#`)

1. **OQ1** *(first pass — superseded by F1/F2: SHA pin + shared vector adopted)* Is the SHA-pin rule
   now the documented convention for every Move dependency across the org?
2. **OQ2** *(first pass — intent confirmed: membership, indefinite decryptability)* Should operators be
   offered a policy that bounds decryptions (would need an on-chain, non-dry-run mechanism)?
3. **OQ3** Burn or multisig for the `UpgradeCap` — on testnet now, and at mainnet publish?
4. **OQ4** Keep `sealed_content::publish` permissionless for launch, or add a curated variant?
5. **OQ5** Will every client disambiguate aborts by `(module, code)`?
6. **OQ6** Which testnet package is canonical — `0x9f0563…` (Published.toml, seal-ui default,
   UpgradeCap recorded) or `0x67520f…` (`Move.toml`, seal-ui `.env.example`)?
7. **OQ7** Should pausing or freezing a gate also stop decryption for existing passes?

## Risks (residual)

- **Key-server liveness:** decryption depends on a threshold of third-party servers; fails closed.
- **Upgrade authority:** until OQ3 executes, one key can change who can decrypt every ciphertext.
- **Indefinite decryptability:** access cannot be revoked once a key is released (by design).
- **Discovery spoofing:** anyone can publish look-alike pointers; only UI filtering protects users.
- **Cross-repo drift:** the identity layout is duplicated in two repos; the shared vector detects
  but does not prevent drift.

---

## Re-verification log

- 2026-09-18 — first-pass baseline (8 → 12 tests; F1–F5; OQ1–OQ5).
- 2026-09-28 — relocated to the package repo; re-verified under the updated template + Sui lens.
  F1 upgraded to RESOLVED (tag found moved; SHA-pinned in `e45afb6`); F6, F7, F11 RESOLVED in
  `e45afb6`; F9 RESOLVED in `e5dbcd5`; F8, F10, F12 added. 21/21 tests. On-chain reads: both testnet
  packages exist; `UpgradeCap 0x20de…` live (compatible) for `0x9f0563…`.
