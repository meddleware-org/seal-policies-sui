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
///
/// Pausing: a paused gate still admits decryption by default. If the gate was created with the
/// `pause_blocks_decryption` policy (passed to `access_gate::create_gate` / `create_free_gate`), decryption
/// is denied while it is paused (`E_GATE_PAUSED`) and resumes when it is unpaused. Such a gate must also have
/// `freeze_requires_unpaused` (`access_gate::new_gate_policy` enforces it), so it can never be frozen while
/// paused: its content cannot be made permanently undecryptable by pausing and then freezing.
///
/// Check order: version, namespace (`E_ID_NOT_NAMESPACED`), pause (`E_GATE_PAUSED`), then pass validity
/// (`E_WRONG_GATE`) and uses (`E_EXHAUSTED`).
///
/// Known property (Seal gives confidentiality only to an object's owner): a holder of a *transferable* pass
/// (`AccessNFT` has `store`) can freeze or share it, after which anyone can present it. Gates used for Sealed
/// Storage should be soulbound; see SECURITY.md.
///
/// Version gating: both entries take the shared `config::PolicyConfig` and abort with
/// `config::E_WRONG_VERSION` under any other package version.
module seal_policies::nft_gate;

use access_gate::access_gate::{Self, Gate, AccessNFT, SoulboundAccessNFT};
use seal_policies::config::{Self, PolicyConfig};

/// Identity is not namespaced to this gate (its first 32 bytes must equal the gate object id).
const E_ID_NOT_NAMESPACED: u64 = 1;
/// The presented NFT was not minted from this gate.
const E_WRONG_GATE: u64 = 2;
/// A single-use pass with zero remaining uses cannot authorise.
const E_EXHAUSTED: u64 = 3;
/// The gate is paused and its policy says pausing blocks decryption.
const E_GATE_PAUSED: u64 = 4;

/// Seal approval for a transferable access NFT.
entry fun seal_approve(id: vector<u8>, policy: &PolicyConfig, gate: &Gate, nft: &AccessNFT) {
    config::check_version(policy);
    assert_namespaced(&id, gate);
    assert_not_paused_if_required(gate);
    assert!(access_gate::is_valid_for(nft, gate), E_WRONG_GATE);
    assert_has_uses(access_gate::uses_remaining(nft));
}

/// Seal approval for a soulbound access NFT.
entry fun seal_approve_soulbound(
    id: vector<u8>,
    policy: &PolicyConfig,
    gate: &Gate,
    nft: &SoulboundAccessNFT,
) {
    config::check_version(policy);
    assert_namespaced(&id, gate);
    assert_not_paused_if_required(gate);
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

/// Honour the gate's `pause_blocks_decryption` policy.
fun assert_not_paused_if_required(gate: &Gate) {
    assert!(
        !(access_gate::gate_pause_blocks_decryption(gate) && access_gate::gate_is_paused(gate)),
        E_GATE_PAUSED,
    );
}

fun assert_has_uses(remaining: Option<u64>) {
    if (remaining.is_some()) {
        assert!(*remaining.borrow() > 0, E_EXHAUSTED);
    };
}
