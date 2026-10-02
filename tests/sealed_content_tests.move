// SPDX-License-Identifier: 0BSD

#[test_only]
module seal_policies::sealed_content_tests;

use seal_policies::config;
use std::string::String;
use seal_policies::sealed_content::{Self, SealedContent};
use sui::test_scenario as ts;

const PUBLISHER: address = @0xC0;
const OTHER: address = @0xD0;

// Publish with a fresh current-version PolicyConfig (the version gate is tested in config_tests).
fun publish_t(s: &mut ts::Scenario, gate_id: ID, blob_id: String, seal_id: String, label: String) {
    let policy = config::new_for_testing(s.ctx());
    sealed_content::publish(&policy, gate_id, blob_id, seal_id, label, s.ctx());
    config::destroy_for_testing(policy);
}

#[test]
fun publish_shares_pointer_and_emits_event() {
    let mut s = ts::begin(PUBLISHER);
    let gate_id = object::id_from_address(@0x123);
    publish_t(
        &mut s,
        gate_id,
        b"blob-1".to_string(),
        b"0xabc".to_string(),
        b"Episode 1".to_string(),
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
    publish_t(
        &mut s,
        arbitrary_gate,
        b"b".to_string(),
        b"s".to_string(),
        b"Official content".to_string(),
    );
    s.next_tx(OTHER);
    let c = s.take_shared<SealedContent>();
    assert!(c.gate_id() == arbitrary_gate, 0);
    assert!(c.publisher() == OTHER, 1);
    ts::return_shared(c);
    s.end();
}

/// `n` copies of the byte `b`, as a String.
fun repeat(b: u8, n: u64): std::string::String {
    let mut v = vector[];
    n.do!(|_| v.push_back(b));
    v.to_string()
}

#[test]
fun accepts_fields_at_their_limits() {
    let mut s = ts::begin(PUBLISHER);
    publish_t(
        &mut s,
        object::id_from_address(@0x123),
        repeat(0x62, 128),
        repeat(0x73, 256),
        repeat(0x6c, 256),
    );
    s.next_tx(PUBLISHER);
    let c = s.take_shared<SealedContent>();
    assert!(c.label().length() == 256, 0);
    ts::return_shared(c);
    s.end();
}

#[test, expected_failure(abort_code = sealed_content::E_LABEL_TOO_LONG)]
fun rejects_a_label_over_the_limit() {
    let mut s = ts::begin(PUBLISHER);
    publish_t(&mut s, object::id_from_address(@0x123), b"b".to_string(), b"s".to_string(), repeat(0x6c, 257));
    s.end();
}

#[test, expected_failure(abort_code = sealed_content::E_BLOB_ID_TOO_LONG)]
fun rejects_a_blob_id_over_the_limit() {
    let mut s = ts::begin(PUBLISHER);
    publish_t(&mut s, object::id_from_address(@0x123), repeat(0x62, 129), b"s".to_string(), b"l".to_string());
    s.end();
}

#[test, expected_failure(abort_code = sealed_content::E_SEAL_ID_TOO_LONG)]
fun rejects_a_seal_id_over_the_limit() {
    let mut s = ts::begin(PUBLISHER);
    publish_t(&mut s, object::id_from_address(@0x123), b"b".to_string(), repeat(0x73, 257), b"l".to_string());
    s.end();
}

#[test]
#[expected_failure(abort_code = 1, location = seal_policies::config)] // E_WRONG_VERSION
fun wrong_version_blocks_publish() {
    let mut s = ts::begin(PUBLISHER);
    let mut policy = config::new_for_testing(s.ctx());
    config::set_version_for_testing(&mut policy, 0);
    sealed_content::publish(
        &policy,
        object::id_from_address(@0x123),
        b"b".to_string(),
        b"s".to_string(),
        b"l".to_string(),
        s.ctx(),
    );
    config::destroy_for_testing(policy);
    s.end();
}
