---
title: Sealed Storage policies — on-chain API reference
---

# Sealed Storage policies — on-chain API reference

Package `seal_policies` (Move 2024). Depends on `access_gate`, pinned to a commit SHA. The live
testnet package `0x9f0563…` was built against `f191c2d…` (→ `access_gate` `0x0bedd0…`, no gate
policies); the source pins `8f38cfb…` (gate policies), which ships with the next access-gate
publish. No `init`, no capabilities, no admin objects.

## `seal_policies::nft_gate` (policy)

| Function | Signature | Checks, in order |
| --- | --- | --- |
| `seal_approve` | `entry fun seal_approve(id: vector<u8>, gate: &Gate, nft: &AccessNFT)` | `id` ≥ 32 bytes and `id[0..32] == object::id_bytes(gate)` (else 1); `access_gate::is_valid_for(nft, gate)` (else 2); not (paused and policy `pause_blocks_decryption`) (else 4); single-use pass has uses > 0 (else 3) |
| `seal_approve_soulbound` | `entry fun seal_approve_soulbound(id: vector<u8>, gate: &Gate, nft: &SoulboundAccessNFT)` | same, via `is_valid_for_soulbound` / `uses_remaining_soulbound` |

Side-effect free: immutable references only; no mutation, transfer, object creation or events.
Pausing a gate blocks decryption **only** if the gate was created with the `access_gate` policy flag
`pause_blocks_decryption`; decryption resumes when the gate is unpaused. `frozen` is never checked.
Keys already released stay usable — pausing stops new key releases, not past ones.

| Code | Constant | Meaning |
| --- | --- | --- |
| 1 | `E_ID_NOT_NAMESPACED` | Identity shorter than 32 bytes or not prefixed with this gate's id |
| 2 | `E_WRONG_GATE` | The NFT was not minted from this gate |
| 3 | `E_EXHAUSTED` | Single-use pass with zero uses remaining |
| 4 | `E_GATE_PAUSED` | Gate is paused and its policy has `pause_blocks_decryption` (source only — not in `0x9f0563…`) |

## `seal_policies::timelock` (policy)

| Function | Signature | Checks |
| --- | --- | --- |
| `seal_approve` | `entry fun seal_approve(id: vector<u8>, clock: &Clock)` | `id` ≥ 8 bytes (else 1); `clock.timestamp_ms() >= u64_be(id[0..8])` (else 2). Suffix bytes ignored. |

Side-effect free. `Clock` is the system object `0x6`.

| Code | Constant | Meaning |
| --- | --- | --- |
| 1 | `E_BAD_ID` | Identity shorter than 8 bytes |
| 2 | `E_TOO_EARLY` | Unlock time not yet reached |

## `seal_policies::sealed_content` (registry — not a policy)

| Item | Definition |
| --- | --- |
| `SealedContent` | `has key, store` (shared on publish): `gate_id: ID`, `blob_id: String`, `seal_id: String`, `label: String`, `publisher: address` |
| `publish` | `entry fun publish(gate_id: ID, blob_id: String, seal_id: String, label: String, ctx)` — permissionless; creates and **shares** a `SealedContent`; emits `SealedContentPublished`. No validation of `gate_id`; no update/delete. |
| `SealedContentPublished` | event (`copy, drop`): `content_id`, `gate_id`, `blob_id`, `seal_id`, `label`, `publisher` |
| Views | `gate_id`, `blob_id`, `seal_id`, `label`, `publisher` |

No abort codes.

## Identity layouts (conformance)

| Policy | Layout | Vector (shared with `seal-client`) |
| --- | --- | --- |
| `nft_gate` | `[32-byte gate id][nonce]` | gate `0x123` → prefix `00…0123` (32 bytes) |
| `timelock` | `[8-byte BE unlock_ms][nonce]` | `1704067200000` → `00 00 01 8c c2 51 f4 00` |

## Invariants

- `seal_approve*` never has side effects and aborts (never grants) on malformed identities.
- An `nft_gate` identity for gate A can never be approved with gate B's pass.
- `timelock` never approves before `unlock_ms`; `unlock_ms = 0` always approves; `u64::MAX` decodes
  without overflow.
