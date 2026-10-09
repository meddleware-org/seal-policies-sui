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

Testnet package: `0x0c8f73490b14836e6a7a724fb46b242cb061d04a5f193fd637159997f8a1773d` (used by
Sealed Storage; `PolicyConfig` `0xee0403ba15c250223527150d147f29bedfb1ec46bb2282c341be462ff0ad7d1a`). It depends on the access-gate package `0xd7ddaa94…`. Content
sealed under a superseded `seal_policies` package (an earlier original id) is **not supported**: the Meddleware clients serve one policy namespace, and the manifest records none. Pre-v0.2 packages are republished rather than migrated, so re-seal content when the package changes. Mainnet: not yet published.

A transferable pass (`AccessNFT` has `store`) can be frozen or shared by its holder, after which anyone can present it and the policy approves: **gates used for Sealed Storage should be soulbound**. A gate whose pause blocks decryption can never be frozen while paused, so pausing and then freezing cannot make its content permanently undecryptable.
