---
title: Sealed Storage policies — on-chain overview
---

# Sealed Storage policies — on-chain overview

`seal_policies` is the on-chain half of **Sealed Storage**: access-control policies for
[Seal](https://seal-docs.wal.app/) threshold encryption. Content is encrypted in the browser under a
Seal **identity**, stored (as ciphertext) on Walrus, and can only be decrypted when a committee of
independent key servers agrees to release key shares. A key server releases its share only if a
policy function in this package — `seal_approve*` — **succeeds in a dry run** with the requester as
the sender. The client half is `@meddleware/seal-client`; each module here mirrors one client
provider.

## Modules

| Module | What it decides | Identity layout |
| --- | --- | --- |
| `nft_gate` | Decrypt only while you hold a valid pass for one specific access gate | `[32-byte gate object id][nonce]` |
| `timelock` | Decrypt only at or after an unlock time | `[8-byte big-endian unlock_ms][nonce]` |
| `sealed_content` | *Not a policy.* A permissionless public registry of pointers (`gate_id`, Walrus `blob_id`, Seal `seal_id`, label) so pass-holders can **discover** unlockable content | — |

## Key properties

- **Policies are read-only.** `seal_approve*` functions take only immutable references; they never
  change, transfer or create anything, so they are safe to dry-run.
- **Ownership is enforced by Seal first.** The key server dry-runs under the requester's address,
  so presenting a pass you do not own fails before policy logic runs; the policy is a second gate.
- **Gate isolation.** An `nft_gate` identity is bound to one gate — a pass for gate A can never
  decrypt content sealed for gate B.
- **Membership, not consumption.** Decrypting does not spend a single-use pass; an exhausted pass is
  rejected, and a released key keeps working for that holder.
- **Liveness.** Decryption needs the key-server committee to be reachable (fails closed); the
  on-chain policies themselves have no liveness dependency beyond the chain (`timelock` reads the
  system `Clock` at `0x6`).

Testnet package: `0x61c4aaa431cc33a41a9db34621e2925fc8eb4e3b3f1d70eaeb8d8c2b73507e42` (used by
Sealed Storage; `PolicyConfig` `0xa5013eb407cac7e48b0b7f1cb5540b0e6115566dd01988b8f11fe77f4ebf3595`). It depends on the access-gate package `0xa55789…`. Content
sealed under the superseded `0x42cc18…` and `0x9f0563…` still decrypts through those packages. Mainnet: not yet published.
