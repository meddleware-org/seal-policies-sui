---
title: Sealed Storage policies — what they allow
---

# Sealed Storage policies — what they allow

When you seal a file in Sealed Storage you pick a **policy**. The policy decides, on-chain, who may
later obtain the decryption key. You do not call these policies yourself — the app encrypts under
the right identity, and the Seal key servers check the policy when someone asks to decrypt.

## Pass-holders only (`nft_gate`)

- **Who can decrypt:** anyone holding a valid pass (transferable or soulbound) for the gate you chose.
- **Single-use passes:** decrypting does **not** spend a use. A pass with uses left can decrypt as
  often as needed; a pass that is used up (zero uses) cannot.
- **Other gates:** a pass for a different gate never works, even from the same creator.
- **Pausing or freezing the gate** does not stop existing pass-holders from decrypting.
- **Transferable passes:** if a pass is sold or sent to someone else, the new holder can decrypt.
- **Once decrypted, always decrypted:** a holder who has decrypted a file keeps the plaintext and
  can obtain the key again while they hold a valid pass. Access cannot be revoked retroactively.

## Unlock at a time (`timelock`)

- **Who can decrypt:** anyone, once the network clock reaches the unlock time.
- **Before that time:** nobody — not even you. Choose the time carefully; it cannot be changed after
  sealing.

## Content listings (`sealed_content`)

Apps can publish a public **pointer** to sealed content ("Episode 1 is available to pass-holders").

- **Anyone can publish a pointer, under any gate, with any label.** A pointer proves nothing about
  who made the content — treat labels as untrusted.
- Pointers grant no access: the file still only decrypts under its policy.

## Limits and safety notes

- Decryption needs the Seal key-server committee to be online; if it is not, sealed files cannot be
  opened until it is (nothing is ever released by default).
- Everything stored is public ciphertext; only the key is controlled by the policy.
- Keep your own copy of anything you cannot afford to lose — storage on Walrus has a lifetime.
