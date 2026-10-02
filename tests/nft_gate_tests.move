// SPDX-License-Identifier: 0BSD

// Abort codes are referenced by literal in #[expected_failure] because module-private
// constants are not cross-module referenceable in that attribute:
//   E_ID_NOT_NAMESPACED = 1, E_WRONG_GATE = 2, E_EXHAUSTED = 3  (see nft_gate.move).
#[test_only]
module seal_policies::nft_gate_tests;

use access_gate::access_gate::{Self, Gate, AdminCap, AccessNFT, SoulboundAccessNFT, GatePolicy, PlatformConfig};
use seal_policies::config;
use seal_policies::nft_gate;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario as ts;

const CREATOR: address = @0xA1;
const HOLDER: address = @0xB0B;

// Share a zero-fee PlatformConfig, then create a free gate with `policy` (ready to take next tx).
fun make_gate_with(s: &mut ts::Scenario, soulbound: bool, default_uses: u64, policy: GatePolicy) {
    access_gate::share_platform_config_zero_commission_for_testing(s.ctx());
    s.next_tx(CREATOR);
    let platform = s.take_shared<PlatformConfig>();
    access_gate::create_free_gate(
        &platform, coin::mint_for_testing<SUI>(0, s.ctx()), CREATOR, default_uses, soulbound, false,
        b"".to_string(), b"".to_string(), b"".to_string(), policy, s.ctx(),
    );
    ts::return_shared(platform);
}

fun make_gate(s: &mut ts::Scenario, soulbound: bool, default_uses: u64) {
    make_gate_with(s, soulbound, default_uses, access_gate::default_gate_policy());
}

// Airdrop a pass from a free gate (the commission due is 0).
fun grant(s: &mut ts::Scenario, cap: &AdminCap, gate: &Gate, recipient: address) {
    let platform = s.take_shared<PlatformConfig>();
    access_gate::airdrop(cap, gate, &platform, coin::mint_for_testing<SUI>(0, s.ctx()), recipient, s.ctx());
    ts::return_shared(platform);
}

// access_gate calls that need the shared PlatformConfig (its version gate). A shared object can be
// taken once per test transaction, so the airdrop and the pause toggles share one borrow.
fun grant_then_set_paused(
    s: &mut ts::Scenario,
    cap: &AdminCap,
    gate: &mut Gate,
    recipient: address,
    states: vector<bool>,
) {
    let platform = s.take_shared<PlatformConfig>();
    access_gate::airdrop(cap, gate, &platform, coin::mint_for_testing<SUI>(0, s.ctx()), recipient, s.ctx());
    states.do!(|paused| access_gate::set_paused(cap, gate, &platform, paused));
    ts::return_shared(platform);
}

fun consume_t(s: &mut ts::Scenario, nft: AccessNFT, gate: &Gate) {
    let platform = s.take_shared<PlatformConfig>();
    access_gate::consume(nft, gate, &platform, b"nonce_suffix", s.ctx());
    ts::return_shared(platform);
}

fun consume_soulbound_t(s: &mut ts::Scenario, nft: SoulboundAccessNFT, gate: &Gate) {
    let platform = s.take_shared<PlatformConfig>();
    access_gate::consume_soulbound(nft, gate, &platform, b"nonce_suffix", s.ctx());
    ts::return_shared(platform);
}

// Call a policy with a fresh current-version PolicyConfig (the version gate is tested in config_tests).
fun approve(s: &mut ts::Scenario, id: vector<u8>, gate: &Gate, nft: &AccessNFT) {
    let policy = config::new_for_testing(s.ctx());
    nft_gate::seal_approve(id, &policy, gate, nft);
    config::destroy_for_testing(policy);
}

fun approve_soulbound(s: &mut ts::Scenario, id: vector<u8>, gate: &Gate, nft: &SoulboundAccessNFT) {
    let policy = config::new_for_testing(s.ctx());
    nft_gate::seal_approve_soulbound(id, &policy, gate, nft);
    config::destroy_for_testing(policy);
}

// A valid identity: the 32-byte gate id followed by a nonce suffix byte.
fun id_for(gate: &Gate): vector<u8> {
    let mut id = object::id_bytes(gate);
    id.push_back(7u8);
    id
}

#[test]
fun approve_unlimited_pass_succeeds() {
    let mut s = ts::begin(CREATOR);
    make_gate(&mut s, false, 0);
    s.next_tx(CREATOR);
    let gate = s.take_shared<Gate>();
    let cap = s.take_from_sender<AdminCap>();
    grant(&mut s, &cap, &gate, HOLDER);
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    approve(&mut s, id_for(&gate), &gate, &nft);
    s.return_to_sender(nft);

    ts::return_shared(gate);
    s.end();
}

#[test]
fun approve_soulbound_pass_succeeds() {
    let mut s = ts::begin(CREATOR);
    make_gate(&mut s, true, 0);
    s.next_tx(CREATOR);
    let gate = s.take_shared<Gate>();
    let cap = s.take_from_sender<AdminCap>();
    grant(&mut s, &cap, &gate, HOLDER);
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<SoulboundAccessNFT>();
    approve_soulbound(&mut s, id_for(&gate), &gate, &nft);
    s.return_to_sender(nft);

    ts::return_shared(gate);
    s.end();
}

// Conformance vector shared bit-for-bit with the client encoder
// (repos/seal-client/tests/conformance-vectors.json → nftGate). Two properties are pinned:
//  1. The identity layout is [32-byte gate id][nonce] — the first 32 bytes equal object::id_bytes.
//  2. The 32-byte gate id is canonical big-endian right-aligned, so a short id like 0x123 encodes to
//     31 zero bytes then 0x01, 0x23 (matching the client's objectIdBytes('0x123')).
#[test]
fun conformance_gate_id_prefix_layout() {
    let mut s = ts::begin(CREATOR);
    make_gate(&mut s, false, 0);
    s.next_tx(CREATOR);
    let gate = s.take_shared<Gate>();

    // Property 1: id_for prefixes the identity with exactly the 32-byte gate id.
    let id = id_for(&gate);
    let gid = object::id_bytes(&gate);
    let mut i = 0u64;
    while (i < 32) {
        assert!(id[i] == gid[i], 200 + i);
        i = i + 1;
    };

    // Property 2: the framework's object-id byte encoding (the same one `assert_namespaced`
    // compares against via `object::id_bytes`) yields the shared vector's prefix for 0x123:
    // 30 zero bytes then 0x01, 0x23 — i.e. canonical big-endian, right-aligned.
    let expected_0x123 = {
        let mut v: vector<u8> = vector[];
        let mut j = 0u64;
        while (j < 30) { v.push_back(0u8); j = j + 1; };
        v.push_back(0x01);
        v.push_back(0x23);
        v
    };
    assert!(object::id_from_address(@0x123).to_bytes() == expected_0x123, 299);

    ts::return_shared(gate);
    s.end();
}

#[test]
#[expected_failure(abort_code = 2)] // E_WRONG_GATE
fun approve_with_foreign_nft_aborts() {
    let mut s = ts::begin(CREATOR);
    make_gate(&mut s, false, 0); // gate A
    make_gate(&mut s, false, 0); // gate B
    s.next_tx(CREATOR);
    // Two gates + two caps exist. Take them in a deterministic order.
    let gate_b = s.take_shared<Gate>();
    let gate_a = s.take_shared<Gate>();
    let cap_a = s.take_from_sender<AdminCap>();
    // cap_a authorises exactly one of the gates; airdrop from whichever it matches.
    if (access_gate::admin_cap_gate_id(&cap_a) == object::id(&gate_a)) {
        grant(&mut s, &cap_a, &gate_a, HOLDER);
    } else {
        grant(&mut s, &cap_a, &gate_b, HOLDER);
    };
    s.return_to_sender(cap_a);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    // Namespace the id to whichever gate the NFT is NOT valid for, so the namespace check
    // passes and the is_valid_for check is what aborts.
    let (target, other) = if (access_gate::is_valid_for(&nft, &gate_a)) {
        (&gate_b, &gate_a)
    } else {
        (&gate_a, &gate_b)
    };
    let _ = other;
    approve(&mut s, id_for(target), target, &nft); // aborts E_WRONG_GATE

    s.return_to_sender(nft);
    ts::return_shared(gate_a);
    ts::return_shared(gate_b);
    s.end();
}

#[test]
#[expected_failure(abort_code = 1)] // E_ID_NOT_NAMESPACED
fun approve_with_wrong_namespace_aborts() {
    let mut s = ts::begin(CREATOR);
    make_gate(&mut s, false, 0);
    s.next_tx(CREATOR);
    let gate = s.take_shared<Gate>();
    let cap = s.take_from_sender<AdminCap>();
    grant(&mut s, &cap, &gate, HOLDER);
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    // 32 zero bytes + suffix — not this gate's id.
    let mut bad: vector<u8> = vector[];
    let mut i = 0u64;
    while (i < 33) { bad.push_back(0u8); i = i + 1; };
    approve(&mut s, bad, &gate, &nft); // aborts E_ID_NOT_NAMESPACED

    s.return_to_sender(nft);
    ts::return_shared(gate);
    s.end();
}

// Boundary: an id with exactly 32 bytes (no nonce suffix) passes `assert_namespaced` so long
// as the bytes match the gate id — the minimum valid identity length.
#[test]
fun approve_with_exact_32_byte_id_succeeds() {
    let mut s = ts::begin(CREATOR);
    make_gate(&mut s, false, 0);
    s.next_tx(CREATOR);
    let gate = s.take_shared<Gate>();
    let cap = s.take_from_sender<AdminCap>();
    grant(&mut s, &cap, &gate, HOLDER);
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    // Exactly 32 bytes = just the gate id, no trailing nonce.
    let id = object::id_bytes(&gate);
    assert!(id.length() == 32, 400);
    approve(&mut s, id, &gate, &nft);
    s.return_to_sender(nft);

    ts::return_shared(gate);
    s.end();
}

// Boundary: an id shorter than 32 bytes aborts with E_ID_NOT_NAMESPACED immediately
// (does not read past bounds or produce a silent gate-mismatch).
#[test]
#[expected_failure(abort_code = 1)] // E_ID_NOT_NAMESPACED
fun approve_with_7_byte_id_aborts() {
    let mut s = ts::begin(CREATOR);
    make_gate(&mut s, false, 0);
    s.next_tx(CREATOR);
    let gate = s.take_shared<Gate>();
    let cap = s.take_from_sender<AdminCap>();
    grant(&mut s, &cap, &gate, HOLDER);
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    let bad: vector<u8> = vector[0, 1, 2, 3, 4, 5, 6]; // 7 bytes < 32
    approve(&mut s, bad, &gate, &nft); // aborts E_ID_NOT_NAMESPACED

    s.return_to_sender(nft);
    ts::return_shared(gate);
    s.end();
}

#[test]
#[expected_failure(abort_code = 3)] // E_EXHAUSTED
fun approve_with_exhausted_pass_aborts() {
    let mut s = ts::begin(CREATOR);
    make_gate(&mut s, false, 1); // single-use, 1 use, auto_burn = false → returns 0-use receipt
    s.next_tx(CREATOR);
    let gate = s.take_shared<Gate>();
    let cap = s.take_from_sender<AdminCap>();
    grant(&mut s, &cap, &gate, HOLDER);
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    consume_t(&mut s, nft, &gate); // decrements 1 → 0, returns receipt

    s.next_tx(HOLDER);
    let spent = s.take_from_sender<AccessNFT>();
    approve(&mut s, id_for(&gate), &gate, &spent); // aborts E_EXHAUSTED

    s.return_to_sender(spent);
    ts::return_shared(gate);
    s.end();
}

// ── Soulbound variants of the abort paths ────────────────────────────────────────

#[test]
#[expected_failure(abort_code = 2)] // E_WRONG_GATE
fun approve_soulbound_with_foreign_nft_aborts() {
    let mut s = ts::begin(CREATOR);
    make_gate(&mut s, true, 0);
    s.next_tx(CREATOR);
    let gate_a = s.take_shared<Gate>();
    let cap = s.take_from_sender<AdminCap>();
    grant(&mut s, &cap, &gate_a, HOLDER);
    s.return_to_sender(cap);
    ts::return_shared(gate_a);

    s.next_tx(CREATOR);
    make_gate(&mut s, true, 0); // gate B (newest shared)
    s.next_tx(HOLDER);
    let gate_b = s.take_shared<Gate>();
    let nft = s.take_from_sender<SoulboundAccessNFT>();
    approve_soulbound(&mut s, id_for(&gate_b), &gate_b, &nft); // NFT is gate A's
    s.return_to_sender(nft);
    ts::return_shared(gate_b);
    s.end();
}

#[test]
#[expected_failure(abort_code = 3)] // E_EXHAUSTED
fun approve_soulbound_with_exhausted_pass_aborts() {
    let mut s = ts::begin(CREATOR);
    make_gate(&mut s, true, 1);
    s.next_tx(CREATOR);
    let gate = s.take_shared<Gate>();
    let cap = s.take_from_sender<AdminCap>();
    grant(&mut s, &cap, &gate, HOLDER);
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<SoulboundAccessNFT>();
    consume_soulbound_t(&mut s, nft, &gate);
    s.next_tx(HOLDER);
    let spent = s.take_from_sender<SoulboundAccessNFT>();
    approve_soulbound(&mut s, id_for(&gate), &gate, &spent);
    s.return_to_sender(spent);
    ts::return_shared(gate);
    s.end();
}

#[test]
fun approve_single_use_pass_with_uses_left_succeeds_without_consuming() {
    // Membership semantics: approving does not spend a use (seal_approve is side-effect free).
    let mut s = ts::begin(CREATOR);
    make_gate(&mut s, false, 2);
    s.next_tx(CREATOR);
    let gate = s.take_shared<Gate>();
    let cap = s.take_from_sender<AdminCap>();
    grant(&mut s, &cap, &gate, HOLDER);
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    approve(&mut s, id_for(&gate), &gate, &nft);
    approve(&mut s, id_for(&gate), &gate, &nft);
    assert!(access_gate::uses_remaining(&nft) == option::some(2), 0);
    s.return_to_sender(nft);
    ts::return_shared(gate);
    s.end();
}

#[test]
fun approve_on_paused_gate_still_succeeds() {
    // Documents current behaviour (see audit OQ): pausing a gate stops purchases, not decryption.
    let mut s = ts::begin(CREATOR);
    make_gate(&mut s, false, 0);
    s.next_tx(CREATOR);
    let mut gate = s.take_shared<Gate>();
    let cap = s.take_from_sender<AdminCap>();
    grant_then_set_paused(&mut s, &cap, &mut gate, HOLDER, vector[true]);
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    approve(&mut s, id_for(&gate), &gate, &nft);
    s.return_to_sender(nft);
    ts::return_shared(gate);
    s.end();
}

// ── Gate policy: pause_blocks_decryption ─────────────────────────────────────────

fun make_policy_gate(s: &mut ts::Scenario, pause_blocks_decryption: bool) {
    make_gate_with(s, false, 0, access_gate::new_gate_policy(false, false, pause_blocks_decryption, false));
}

// Airdrop a pass, pause the gate, then approve as the holder.
fun approve_while_paused(pause_blocks_decryption: bool) {
    let mut s = ts::begin(CREATOR);
    make_policy_gate(&mut s, pause_blocks_decryption);
    s.next_tx(CREATOR);
    let mut gate = s.take_shared<Gate>();
    let cap = s.take_from_sender<AdminCap>();
    grant_then_set_paused(&mut s, &cap, &mut gate, HOLDER, vector[true]);
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    approve(&mut s, id_for(&gate), &gate, &nft);
    s.return_to_sender(nft);
    ts::return_shared(gate);
    s.end();
}

#[test]
#[expected_failure(abort_code = 4)] // E_GATE_PAUSED
fun approve_denied_while_paused_when_policy_blocks_decryption() {
    approve_while_paused(true);
}

#[test]
fun approve_allowed_while_paused_without_policy() {
    approve_while_paused(false);
}

#[test]
fun approve_resumes_after_unpause_when_policy_blocks_decryption() {
    let mut s = ts::begin(CREATOR);
    make_policy_gate(&mut s, true);
    s.next_tx(CREATOR);
    let mut gate = s.take_shared<Gate>();
    let cap = s.take_from_sender<AdminCap>();
    grant_then_set_paused(&mut s, &cap, &mut gate, HOLDER, vector[true, false]);
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    approve(&mut s, id_for(&gate), &gate, &nft);
    s.return_to_sender(nft);
    ts::return_shared(gate);
    s.end();
}


// ── Version gate ─────────────────────────────────────────────────────────────────

// A valid pass that would be approved at the current version, checked against another version.
fun approve_at_version(soulbound: bool, version: u64) {
    let mut s = ts::begin(CREATOR);
    make_gate(&mut s, soulbound, 0);
    s.next_tx(CREATOR);
    let gate = s.take_shared<Gate>();
    let cap = s.take_from_sender<AdminCap>();
    grant(&mut s, &cap, &gate, HOLDER);
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let mut policy = config::new_for_testing(s.ctx());
    config::set_version_for_testing(&mut policy, version);
    if (soulbound) {
        let nft = s.take_from_sender<SoulboundAccessNFT>();
        nft_gate::seal_approve_soulbound(id_for(&gate), &policy, &gate, &nft);
        s.return_to_sender(nft);
    } else {
        let nft = s.take_from_sender<AccessNFT>();
        nft_gate::seal_approve(id_for(&gate), &policy, &gate, &nft);
        s.return_to_sender(nft);
    };
    config::destroy_for_testing(policy);
    ts::return_shared(gate);
    s.end();
}

#[test]
fun approve_at_current_version_succeeds() {
    approve_at_version(false, config::package_version());
}

#[test]
#[expected_failure(abort_code = 1, location = seal_policies::config)] // E_WRONG_VERSION
fun wrong_version_blocks_seal_approve() {
    approve_at_version(false, config::package_version() + 1);
}

#[test]
#[expected_failure(abort_code = 1, location = seal_policies::config)] // E_WRONG_VERSION
fun wrong_version_blocks_seal_approve_soulbound() {
    approve_at_version(true, 0);
}
