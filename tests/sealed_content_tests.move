// SPDX-License-Identifier: 0BSD

#[test_only]
module seal_policies::sealed_content_tests;

use seal_policies::sealed_content::{Self, SealedContent};
use sui::test_scenario as ts;

const PUBLISHER: address = @0xC0;
const OTHER: address = @0xD0;

#[test]
fun publish_shares_pointer_and_emits_event() {
    let mut s = ts::begin(PUBLISHER);
    let gate_id = object::id_from_address(@0x123);
    sealed_content::publish(
        gate_id,
        b"blob-1".to_string(),
        b"0xabc".to_string(),
        b"Episode 1".to_string(),
        s.ctx(),
    );
    let effects = s.next_tx(PUBLISHER);
    assert!(effects.num_user_events() == 1, 0);
    assert!(effects.shared().length() == 1, 1);

    let c = s.take_shared<SealedContent>();
    assert!(c.gate_id() == gate_id, 2);
    assert!(c.blob_id() == b"blob-1".to_string(), 3);
    assert!(c.seal_id() == b"0xabc".to_string(), 4);
    assert!(c.label() == b"Episode 1".to_string(), 5);
    assert!(c.publisher() == PUBLISHER, 6);
    ts::return_shared(c);
    s.end();
}

#[test]
fun publish_is_permissionless_and_unvalidated() {
    // Documents the audited property (B.4): ANY sender may publish a pointer under ANY gate id —
    // the gate id is not checked to exist and the sender need not administer it. Discovery UIs
    // must therefore not trust label/publisher; confidentiality is unaffected (Seal gates keys).
    let mut s = ts::begin(OTHER);
    let arbitrary_gate = object::id_from_address(@0xDEAD);
    sealed_content::publish(
        arbitrary_gate,
        b"b".to_string(),
        b"s".to_string(),
        b"Official content".to_string(),
        s.ctx(),
    );
    s.next_tx(OTHER);
    let c = s.take_shared<SealedContent>();
    assert!(c.gate_id() == arbitrary_gate, 0);
    assert!(c.publisher() == OTHER, 1);
    ts::return_shared(c);
    s.end();
}
