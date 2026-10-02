---
title: Sealed Storage policies — developer integration
---

# Sealed Storage policies — developer integration

How to encrypt under these policies, build the approve transaction for Seal key servers, discover
content, and add a new policy. The full on-chain surface is in the [API reference](api-reference.md).
The TypeScript side is `@meddleware/seal-client` (policy registry + `SealController`).

## Normative integration rules

1. **Identity bytes MUST match the on-chain decoder bit-for-bit.**
   - `nft_gate`: `[32-byte gate object id][nonce]` — the gate id is the canonical 32-byte
     big-endian address (`0x123` → 30 zero bytes, `0x01`, `0x23`).
   - `timelock`: `[8-byte big-endian u64 unlock_ms][nonce]`.
   Use `seal-client`'s `bytes.ts` helpers; do not hand-roll encoders. Both repos assert the same
   conformance vector (`seal-client/tests/conformance-vectors.json` ↔ the `conformance_*` Move
   tests) — a layout change MUST update both sides together.
2. **Persist the identity verbatim.** The Seal identity (hex) is part of the ciphertext's
   `SealedManifest`; it cannot be recomputed because it contains a random nonce.
3. **Call the matching approve variant.** `seal_approve` for `AccessNFT`,
   `seal_approve_soulbound` for `SoulboundAccessNFT`; pass the shared `PolicyConfig`
   (`deployments.json` → `policyConfigId`), the gate and the requester's NFT as object arguments.
4. **Never treat `sealed_content` pointers as authenticated.** `publish` is permissionless and does
   not validate `gate_id` or the publisher's relationship to the gate. Filter or curate listings in
   the UI (e.g. only show pointers whose `publisher` is the gate's known operator).
5. **Disambiguate aborts by `(module, code)`.** `nft_gate`, `timelock` and `config` all use code
   `1`, and `access_gate` reuses small integers too. `config` code `1` (`E_WRONG_VERSION`) means the
   called package version has been retired — rebuild the PTB against the current `published-at`.
6. **Surface a paused gate distinctly.** `nft_gate` code `4` (`E_GATE_PAUSED`) means the gate is
   paused and its policy blocks decryption while paused — tell the user access resumes when the
   operator unpauses, rather than reporting a missing or invalid pass.

## The approve PTB (what the key server dry-runs)

```ts
import { Transaction } from '@mysten/sui/transactions'

const tx = new Transaction()
tx.moveCall({
  target: `${SEAL_POLICIES_PKG}::nft_gate::seal_approve`, // or seal_approve_soulbound
  arguments: [
    tx.pure.vector('u8', identityBytes), // [gate id (32)][nonce]
    tx.object(POLICY_CONFIG_ID),         // shared version object (deployments.json)
    tx.object(GATE_ID),
    tx.object(NFT_ID),                   // must be owned by the requesting address
  ],
})
const txBytes = await tx.build({ client, onlyTransactionKind: true })
// hand txBytes to SealClient.fetchKeys / decrypt together with the SessionKey
```

For `timelock`: `target: ${PKG}::timelock::seal_approve`, arguments
`[tx.pure.vector('u8', identityBytes), tx.object(POLICY_CONFIG_ID), tx.object('0x6')]`.
`sealed_content::publish` takes `PolicyConfig` first as well.

## Discovering content

Index `SealedContentPublished` events by `gate_id`, or enumerate shared `SealedContent` objects.
Each carries `blob_id` (Walrus ciphertext), `seal_id` (identity hex), `label` and `publisher`.

## Adding a policy

A new policy is a **new module** with its own `seal_approve*` entry function — existing modules are
never edited — plus one new provider in `seal-client` whose `buildId`/`buildApprove` mirror it and whose
`verifyId` checks the identity layout (required; `decrypt` calls it before every approve).
A policy function MUST take `&PolicyConfig` second and call `config::check_version` first, MUST take
only immutable references, MUST NOT transfer, create, mutate or emit anything, and MUST length-check
every identity byte it reads.

## Liveness

Decryption depends on the Seal key-server committee (a threshold of servers must be reachable); if
it is not, decryption fails closed. Encryption needs only the committee's public keys.
