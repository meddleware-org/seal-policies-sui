---
title: Sealed Storage policies — on-chain API reference
---

# Sealed Storage policies — on-chain API reference

Package `seal_policies` (Move 2024), testnet `0x61c4aaa4…7e42`. Depends on `access_gate` `0xa55789…`
(git dependency pinned to a commit SHA). `config::init` shares one `PolicyConfig` and gives the
`PolicyAdminCap` to the publisher; every entry below takes `policy: &PolicyConfig` and checks its
version first.

## `seal_policies::nft_gate` (policy)

| Function | Signature | Checks, in order |
| --- | --- | --- |
| `seal_approve` | `entry fun seal_approve(id: vector<u8>, policy: &PolicyConfig, gate: &Gate, nft: &AccessNFT)` | in this order: version (else `config` 1); `id` ≥ 32 bytes and `id[0..32] == object::id_bytes(gate)` (else 1); not (paused and policy `pause_blocks_decryption`) (else 4); `access_gate::is_valid_for(nft, gate)` (else 2); single-use pass has uses > 0 (else 3). So a paused policy gate presented with a foreign pass aborts 4, not 2. |
| `seal_approve_soulbound` | `entry fun seal_approve_soulbound(id: vector<u8>, policy: &PolicyConfig, gate: &Gate, nft: &SoulboundAccessNFT)` | same, via `is_valid_for_soulbound` / `uses_remaining_soulbound` |

Side-effect free: immutable references only; no mutation, transfer, object creation or events.
Pausing a gate blocks decryption **only** if the gate was created with the `access_gate` policy flag
`pause_blocks_decryption`; decryption resumes when the gate is unpaused. `frozen` is never checked.
Keys already released stay usable — pausing stops new key releases, not past ones.

| Code | Constant | Meaning |
| --- | --- | --- |
| 1 | `E_ID_NOT_NAMESPACED` | Identity shorter than 32 bytes or not prefixed with this gate's id |
| 2 | `E_WRONG_GATE` | The NFT was not minted from this gate |
| 3 | `E_EXHAUSTED` | Single-use pass with zero uses remaining |
| 4 | `E_GATE_PAUSED` | Gate is paused and its policy has `pause_blocks_decryption` (not in the superseded `0x9f0563…`) |

## `seal_policies::timelock` (policy)

| Function | Signature | Checks |
| --- | --- | --- |
| `seal_approve` | `entry fun seal_approve(id: vector<u8>, policy: &PolicyConfig, clock: &Clock)` | version (else `config` 1); `id` ≥ 8 bytes (else 1); `clock.timestamp_ms() >= u64_be(id[0..8])` (else 2). Suffix bytes ignored. |

Side-effect free. `Clock` is the system object `0x6`.

| Code | Constant | Meaning |
| --- | --- | --- |
| 1 | `E_BAD_ID` | Identity shorter than 8 bytes |
| 2 | `E_TOO_EARLY` | Unlock time not yet reached |

## `seal_policies::sealed_content` (registry — not a policy)

| Item | Definition |
| --- | --- |
| `SealedContent` | `has key, store` (shared on publish): `gate_id: ID`, `blob_id: String`, `seal_id: String`, `label: String`, `publisher: address` |
| `publish` | `entry fun publish(policy: &PolicyConfig, gate_id: ID, blob_id: String, seal_id: String, label: String, ctx)` — version (else `config` 1); permissionless; creates and **shares** a `SealedContent`; emits `SealedContentPublished`. No validation of `gate_id`; no update/delete. |
| `SealedContentPublished` | event (`copy, drop`): `content_id`, `gate_id`, `blob_id`, `seal_id`, `label`, `publisher` |
| Views | `gate_id`, `blob_id`, `seal_id`, `label`, `publisher` |

| Code | Constant | Meaning |
| --- | --- | --- |
| 1 | `E_LABEL_TOO_LONG` | `label` longer than 256 bytes |
| 2 | `E_BLOB_ID_TOO_LONG` | `blob_id` longer than 128 bytes |
| 3 | `E_SEAL_ID_TOO_LONG` | `seal_id` longer than 256 bytes |

## `seal_policies::config` (version gate — not a policy)

| Item | Definition |
| --- | --- |
| `PolicyConfig` | `has key` (shared by `init`): `version: u64` |
| `PolicyAdminCap` | `has key, store` (to the publisher; custody per `CUSTODY.md`) |
| `migrate` | `public fun migrate(_cap: &PolicyAdminCap, config: &mut PolicyConfig)` — sets `version` to this package's `VERSION`; forward only; emits `PolicyConfigMigratedEvent { from_version, to_version }` |
| `check_version` | `public(package)` — aborts unless `config.version == VERSION` |
| Views | `version(config)`, `package_version()` |

| Code | Constant | Meaning |
| --- | --- | --- |
| 1 | `E_WRONG_VERSION` | `PolicyConfig` names another package version (this code is retired, or not yet migrated to) |
| 2 | `E_NOT_UPGRADE` | `migrate` called when the config is already at or past this version |

Abort codes are per module: a client distinguishes `config` 1 from `nft_gate` 1 by the abort location.

## Identity layouts (conformance)

| Policy | Layout | Vector (shared with `seal-client`) |
| --- | --- | --- |
| `nft_gate` | `[32-byte gate id][nonce]` | gate `0x123` → prefix `00…0123` (32 bytes) |
| `timelock` | `[8-byte BE unlock_ms][nonce]` | `1704067200000` → `00 00 01 8c c2 51 f4 00` |

## Invariants

- `seal_approve*` never has side effects and aborts (never grants) on malformed identities.
- Every entry aborts under any package version other than the one `PolicyConfig` names; `migrate` only
  moves forward.
- An `nft_gate` identity for gate A can never be approved with gate B's pass.
- `timelock` never approves before `unlock_ms`; `unlock_ms = 0` always approves; `u64::MAX` decodes
  without overflow.
