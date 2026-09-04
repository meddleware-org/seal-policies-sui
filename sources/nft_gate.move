// SPDX-License-Identifier: 0BSD

/// Seal access policy — gate decryption on ownership of a valid access-gate NFT.
///
/// This is ONE Seal policy among several (see `timelock`); it is **not** privileged. A Seal
/// key server evaluates `seal_approve*` via `dry_run_transaction_block` with the requester's
/// address as the sender, so an `AccessNFT` / `SoulboundAccessNFT` the requester does not own
/// fails input-ownership validation before this logic runs. On top of that we bind the
/// ciphertext to a single gate by requiring the identity's first 32 bytes to equal the gate's
/// object id (`assert_namespaced`), so a pass for gate A cannot decrypt content sealed for
/// gate B.
///
/// Note: `seal_approve` must be side-effect free, so a single-use pass acts as *membership*
/// here (it is not consumed per decryption) — we only reject a pass already exhausted to zero.
module seal_policies::nft_gate;

use access_gate::access_gate::{Self, Gate, AccessNFT, SoulboundAccessNFT};

/// Identity is not namespaced to this gate (its first 32 bytes must equal the gate object id).
const E_ID_NOT_NAMESPACED: u64 = 1;
/// The presented NFT was not minted from this gate.
const E_WRONG_GATE: u64 = 2;
/// A single-use pass with zero remaining uses cannot authorise.
const E_EXHAUSTED: u64 = 3;

/// Seal approval for a transferable access NFT.
entry fun seal_approve(id: vector<u8>, gate: &Gate, nft: &AccessNFT) {
    assert_namespaced(&id, gate);
    assert!(access_gate::is_valid_for(nft, gate), E_WRONG_GATE);
    assert_has_uses(access_gate::uses_remaining(nft));
}

/// Seal approval for a soulbound access NFT.
entry fun seal_approve_soulbound(id: vector<u8>, gate: &Gate, nft: &SoulboundAccessNFT) {
    assert_namespaced(&id, gate);
    assert!(access_gate::is_valid_for_soulbound(nft, gate), E_WRONG_GATE);
    assert_has_uses(access_gate::uses_remaining_soulbound(nft));
}

/// The identity must begin with the 32-byte object id of `gate`.
fun assert_namespaced(id: &vector<u8>, gate: &Gate) {
    assert!(id.length() >= 32, E_ID_NOT_NAMESPACED);
    let gid = object::id_bytes(gate);
    let mut i = 0;
    while (i < 32) {
        assert!(id[i] == gid[i], E_ID_NOT_NAMESPACED);
        i = i + 1;
    };
}

fun assert_has_uses(remaining: Option<u64>) {
    if (remaining.is_some()) {
        assert!(*remaining.borrow() > 0, E_EXHAUSTED);
    };
}
