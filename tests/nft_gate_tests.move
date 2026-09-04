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
    access_gate::consume(nft, &gate, b"nonce", s.ctx()); // decrements 1 → 0, returns receipt

    s.next_tx(HOLDER);
    let spent = s.take_from_sender<AccessNFT>();
    nft_gate::seal_approve(id_for(&gate), &gate, &spent); // aborts E_EXHAUSTED

    s.return_to_sender(spent);
    ts::return_shared(gate);
    s.end();
}
