# Security Policy

## Scope

This policy covers security issues in:

- The Move policy modules (`sources/nft_gate.move`, `sources/timelock.move`) — a bypass that lets an
  unauthorized party pass `seal_approve*`, a cross-gate namespacing escape, a side effect in a
  dry-run policy, or a timelock parsed to the wrong unlock time
- The discovery registry (`sources/sealed_content.move`) as it affects integrity of published
  pointers
- The published testnet package at
  `0x9f0563bfe42fbd29932cd280cc47efe17f5339b4dc569eb110114665eecc231e`

It does not cover:

- **Seal** itself or the key-server committee (report to the
  [Seal project](https://seal-docs.wal.app/)) — the committee enforces object ownership via
  `dry_run` under the requester's address *before* policy logic runs; policies are a second gate
- The `access-gate-sui` package it depends on (see that repo's `SECURITY.md`)
- The client-side identity encoder `@meddleware/seal-client` (`bytes.ts`) — the byte layouts here
  and there must match bit-for-bit; a client-only drift is reported against that package
- Operator key custody of the `UpgradeCap`

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

Known, intentional properties (not vulnerabilities):

- **`sealed_content::publish` is permissionless and is not a policy.** Anyone can publish a pointer
  under any `gate_id` (existence and admin rights are not checked), with any label. Pointers grant
  nothing — decryption still requires `nft_gate::seal_approve*` to pass — but discovery UIs must not
  trust labels or publishers.
- **Membership, not consumption.** A valid pass authorises decryption repeatedly; once a key is
  released the content stays decryptable by that holder indefinitely. Pausing or freezing the gate
  does not revoke decryption for existing passes.
- **Upgrade authority.** The testnet package `0x9f0563…` still has a live `UpgradeCap`
  (`0x20de324f…a1a0`); burning it or moving it to a multisig is a pre-mainnet gate in the audit
  (`docs/audit/seal-policies-sui-audit.md`).

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
