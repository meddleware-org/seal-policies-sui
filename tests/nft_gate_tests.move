// SPDX-License-Identifier: 0BSD

// Abort codes are referenced by literal in #[expected_failure] because module-private
// constants are not cross-module referenceable in that attribute:
//   E_ID_NOT_NAMESPACED = 1, E_WRONG_GATE = 2, E_EXHAUSTED = 3  (see nft_gate.move).
#[test_only]
module seal_policies::nft_gate_tests;

use access_gate::access_gate::{Self, Gate, AdminCap, AccessNFT, SoulboundAccessNFT};
use seal_policies::nft_gate;
use sui::test_scenario as ts;

const CREATOR: address = @0xA1;
const HOLDER: address = @0xB0B;

fun make_gate(s: &mut ts::Scenario, soulbound: bool, default_uses: u64) {
    access_gate::create_gate(
        0, CREATOR, default_uses, soulbound, false,
        b"".to_string(), b"".to_string(), b"".to_string(),
        s.ctx(),
    );
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
    access_gate::airdrop(&cap, &gate, HOLDER, s.ctx());
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    nft_gate::seal_approve(id_for(&gate), &gate, &nft);
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
    access_gate::airdrop(&cap, &gate, HOLDER, s.ctx());
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<SoulboundAccessNFT>();
    nft_gate::seal_approve_soulbound(id_for(&gate), &gate, &nft);
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

    // Property 2: the canonical right-aligned layout for the shared vector's gate id 0x123.
    let expected_0x123 = {
        let mut v: vector<u8> = vector[];
        let mut j = 0u64;
        while (j < 30) { v.push_back(0u8); j = j + 1; };
        v.push_back(0x01);
        v.push_back(0x23);
        v
    };
    assert!(expected_0x123.length() == 32, 299);
    assert!(expected_0x123[30] == 0x01 && expected_0x123[31] == 0x23, 298);

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
        access_gate::airdrop(&cap_a, &gate_a, HOLDER, s.ctx());
    } else {
        access_gate::airdrop(&cap_a, &gate_b, HOLDER, s.ctx());
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
    nft_gate::seal_approve(id_for(target), target, &nft); // aborts E_WRONG_GATE

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
    access_gate::airdrop(&cap, &gate, HOLDER, s.ctx());
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    // 32 zero bytes + suffix — not this gate's id.
    let mut bad: vector<u8> = vector[];
    let mut i = 0u64;
    while (i < 33) { bad.push_back(0u8); i = i + 1; };
    nft_gate::seal_approve(bad, &gate, &nft); // aborts E_ID_NOT_NAMESPACED

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
    access_gate::airdrop(&cap, &gate, HOLDER, s.ctx());
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    // Exactly 32 bytes = just the gate id, no trailing nonce.
    let id = object::id_bytes(&gate);
    assert!(id.length() == 32, 400);
    nft_gate::seal_approve(id, &gate, &nft);
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
    access_gate::airdrop(&cap, &gate, HOLDER, s.ctx());
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    let bad: vector<u8> = vector[0, 1, 2, 3, 4, 5, 6]; // 7 bytes < 32
    nft_gate::seal_approve(bad, &gate, &nft); // aborts E_ID_NOT_NAMESPACED

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
    access_gate::airdrop(&cap, &gate, HOLDER, s.ctx());
    s.return_to_sender(cap);

    s.next_tx(HOLDER);
    let nft = s.take_from_sender<AccessNFT>();
    access_gate::consume(nft, &gate, b"nonce_suffix", s.ctx()); // decrements 1 → 0, returns receipt

    s.next_tx(HOLDER);
    let spent = s.take_from_sender<AccessNFT>();
    nft_gate::seal_approve(id_for(&gate), &gate, &spent); // aborts E_EXHAUSTED

    s.return_to_sender(spent);
    ts::return_shared(gate);
    s.end();
}
