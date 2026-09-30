// SPDX-License-Identifier: 0BSD

/// On-chain pointers binding Seal-encrypted Walrus blobs to an access gate, so pass-holders
/// can DISCOVER unlockable content for a gate and decrypt it via `nft_gate::seal_approve`.
///
/// This lives here (not in `access_gate`, which is deliberately consumer-agnostic) so the
/// access-gate primitive stays untouched — this is the additive half of the "Access Gate →
/// unlockable content" composition. Publishing is permissionless: confidentiality is enforced
/// by Seal + `nft_gate`, not by this object. `blob_id` and `seal_id` are PUBLIC pointers to
/// ciphertext; only gate pass-holders can obtain the decryption key from the key servers.
///
/// Discovery: index `SealedContentPublished` by `gate_id`, or enumerate the shared
/// `SealedContent` objects.
module seal_policies::sealed_content;

use std::string::String;
use sui::event;

/// Longest accepted `label` (bytes). Labels are shown in unlock UIs and copied into every
/// `SealedContentPublished` event, so an unbounded one only costs indexers and viewers.
const MAX_LABEL_BYTES: u64 = 256;
/// Longest accepted `blob_id` (bytes). A Walrus blob id is 43 base64url characters.
const MAX_BLOB_ID_BYTES: u64 = 128;
/// Longest accepted `seal_id` (bytes). The largest identity here (nft-gate: 48 bytes) is 98 hex
/// characters with the `0x` prefix.
const MAX_SEAL_ID_BYTES: u64 = 256;

/// `label` exceeds `MAX_LABEL_BYTES`.
const E_LABEL_TOO_LONG: u64 = 1;
/// `blob_id` exceeds `MAX_BLOB_ID_BYTES`.
const E_BLOB_ID_TOO_LONG: u64 = 2;
/// `seal_id` exceeds `MAX_SEAL_ID_BYTES`.
const E_SEAL_ID_TOO_LONG: u64 = 3;

/// A public pointer binding an encrypted Walrus blob to a gate.
public struct SealedContent has key, store {
    id: UID,
    /// The access gate whose valid pass-holders may decrypt this content.
    gate_id: ID,
    /// Walrus blob id of the ciphertext.
    blob_id: String,
    /// Seal identity (hex) the content was encrypted under.
    seal_id: String,
    /// Human-readable label shown in unlock UIs.
    label: String,
    /// Who published this pointer (informational).
    publisher: address,
}

/// Emitted on publish so front-ends can index unlockable content by `gate_id`.
public struct SealedContentPublished has copy, drop {
    content_id: ID,
    gate_id: ID,
    blob_id: String,
    seal_id: String,
    label: String,
    publisher: address,
}

/// Publish a sealed-content pointer for `gate_id`. Permissionless — the ciphertext is already
/// gated by Seal, so a pointer grants nothing on its own. The three strings are length-bounded
/// (`E_LABEL_TOO_LONG` / `E_BLOB_ID_TOO_LONG` / `E_SEAL_ID_TOO_LONG`).
entry fun publish(
    gate_id: ID,
    blob_id: String,
    seal_id: String,
    label: String,
    ctx: &mut TxContext,
) {
    assert!(label.length() <= MAX_LABEL_BYTES, E_LABEL_TOO_LONG);
    assert!(blob_id.length() <= MAX_BLOB_ID_BYTES, E_BLOB_ID_TOO_LONG);
    assert!(seal_id.length() <= MAX_SEAL_ID_BYTES, E_SEAL_ID_TOO_LONG);
    let content = SealedContent {
        id: object::new(ctx),
        gate_id,
        blob_id,
        seal_id,
        label,
        publisher: ctx.sender(),
    };
    event::emit(SealedContentPublished {
        content_id: object::id(&content),
        gate_id,
        blob_id,
        seal_id,
        label,
        publisher: ctx.sender(),
    });
    transfer::share_object(content);
}

// ── Views ────────────────────────────────────────────────────────────────────────
public fun gate_id(c: &SealedContent): ID { c.gate_id }
public fun blob_id(c: &SealedContent): String { c.blob_id }
public fun seal_id(c: &SealedContent): String { c.seal_id }
public fun label(c: &SealedContent): String { c.label }
public fun publisher(c: &SealedContent): address { c.publisher }
