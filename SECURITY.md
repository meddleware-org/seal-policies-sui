# Security Policy

## Scope

This policy covers security issues in:

- The Move policy modules (`sources/nft_gate.move`, `sources/timelock.move`) and the version gate
  (`sources/config.move`, which invariant 6 relies on) — a bypass that lets an
  unauthorized party pass `seal_approve*`, a cross-gate namespacing escape, a side effect in a
  dry-run policy, or a timelock parsed to the wrong unlock time
- The discovery registry (`sources/sealed_content.move`) as it affects integrity of published
  pointers
- The published testnet package at
  `0x0c8f73490b14836e6a7a724fb46b242cb061d04a5f193fd637159997f8a1773d` (and the superseded `0x61c4aaa431cc33a41a9db34621e2925fc8eb4e3b3f1d70eaeb8d8c2b73507e42`, `0x42cc181f851ef702c1fddc9b925553f03b71784edff49d80fbc260055f86d612`
  while content sealed under it is in use)

It does not cover:

- **Seal** itself or the key-server committee (report to the
  [Seal project](https://seal-docs.wal.app/)) — the committee enforces object ownership via
  `dry_run` under the requester's address *before* policy logic runs; policies are a second gate
- The `access-gate-sui` package it depends on (see that repo's `SECURITY.md`)
- The client-side identity encoder `@meddleware/seal-client` (`bytes.ts`) — the byte layouts here
  and there must match bit-for-bit; a client-only drift is reported against that package
- Custody of the `UpgradeCap` and `PolicyAdminCap` (the multisig process in `CUSTODY.md`), and the custody
  scripts themselves (`publish.sh`, `transfer-authority.sh`, `upgrade.sh`, `migrate.sh`, `make-immutable.sh`)

## Security model (invariants)

These invariants are load-bearing. A report demonstrating that any is violated is in scope and
treated as high severity:

1. **`seal_approve*` is side-effect free.** Policy functions take only immutable references (plus a
   value identity) and never mutate state, transfer, or create objects. They are dry-run, not
   executed.
2. **Identity is namespaced to a gate.** `nft_gate` asserts the identity's first 32 bytes equal the
   gate object id; a pass for gate A cannot decrypt content namespaced to gate B.
3. **Exhausted passes are rejected; unlimited passes always admit.** A zero-use single-use pass
   aborts (`E_EXHAUSTED`); a `none`-uses pass is membership and always admits.
4. **Timelock admits only at/after the unlock time.** `timelock::seal_approve` decodes an 8-byte
   big-endian `unlock_ms` and aborts before `Clock.timestamp_ms() >= unlock_ms`.
5. **Malformed identity input aborts cleanly.** Length guards precede all indexing; a short or
   malformed identity aborts rather than reading out of bounds.
6. **Only the current package version acts.** Every `seal_approve*` and `sealed_content::publish`
   aborts (`config::E_WRONG_VERSION`) unless the shared `PolicyConfig` names this package version;
   `migrate` (needs `PolicyAdminCap`) only moves forward and retires every older version at once.

Known, intentional properties (not vulnerabilities):

- **A transferable pass can be frozen into public access.** `AccessNFT` has `store`, so its holder can
  `public_freeze_object` or share it; a frozen pass is an immutable object anyone can present, and
  `nft_gate::seal_approve` approves it (tested: `a_frozen_transferable_pass_still_approves_for_anyone`). Only
  a soulbound pass (`SoulboundAccessNFT`, no `store`) cannot be frozen or shared by its holder. **Gates
  used for Sealed Storage should be soulbound**; `@meddleware/seal-client` refuses to seal to a transferable
  gate unless asked to.
- **Content sealed under a superseded package is unsupported.** Each `seal_policies` original id is its own Seal
  namespace; the clients serve the current one only.
- **Coupled releases.** `nft_gate` reads `access_gate` through its linkage: an `access_gate` *upgrade* that
  changes a view does not reach `nft_gate` until this package is upgraded with the new linkage, and an
  `access_gate` *republish* makes the new gates incompatible types, so `seal_policies` is republished against
  it (CUSTODY.md, "Coupled releases").
- **Timelock depends on each key server's clock.** Servers dry-run against their own full node's `Clock`, so
  the unlock instant is approximate (seconds) and servers may briefly disagree around it; there is no upper
  bound on `unlock_ms`.

- **`sealed_content::publish` is permissionless and is not a policy.** Anyone can publish a pointer
  under any `gate_id` (existence and admin rights are not checked), with any label. Pointers grant
  nothing — decryption still requires `nft_gate::seal_approve*` to pass — but discovery UIs must not
  trust labels or publishers.
- **Membership, not consumption.** A valid pass authorises decryption repeatedly; once a key is
  released the content stays decryptable by that holder indefinitely. Freezing a gate never affects
  decryption; pausing blocks **new** key releases only for gates created with the
  `pause_blocks_decryption` policy (`E_GATE_PAUSED`) — keys already released cannot be revoked.
- **Upgrade authority.** Each full release follows `CUSTODY.md`: the UpgradeCap moves to the custody
  multisig after publishing and the multisig burns it on a planned date after a verification window.
  The testnet package `0x0c8f7349…773d` (2026-10-09) has a live `UpgradeCap` (`0x41ecc649…f574`,
  publisher EOA), recorded in `deployments.json`. The superseded `0x61c4aa…` is immutable
  (its cap `0x12ee376f…5a74` was burned on 2026-10-09), as is `0x42cc18…`
  (its cap `0x0ff7fa39…912f` was burned on 2026-10-02), as are the older superseded and stray
  packages (caps burned 2026-09-28).

## Supported versions

Only the latest published package receives security fixes.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Report vulnerabilities by emailing **<security@meddleware.co.uk>**. Include:

- A description of the vulnerability and its impact
- Steps to reproduce or a proof-of-concept (if available)
- The package address or commit SHA you tested against

You will receive an acknowledgement within **3 business days** and a resolution plan within
**14 days** for confirmed issues. Critical issues (CVSS ≥ 9.0) are prioritised for same-day
acknowledgement.

## Disclosure

Once a fix is released, a security advisory will be published on the GitHub repository. Reporters
may be credited by name unless they prefer to remain anonymous.
