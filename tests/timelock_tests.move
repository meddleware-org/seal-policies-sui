// SPDX-License-Identifier: 0BSD

// Abort codes by literal (see timelock.move): E_BAD_ID = 1, E_TOO_EARLY = 2.
#[test_only]
module seal_policies::timelock_tests;

use seal_policies::timelock;
use sui::clock;
use sui::test_scenario as ts;

const U: address = @0xA1;

// Encode `unlock_ms` big-endian into 8 bytes, then a suffix nonce byte.
fun id_for_unlock(unlock_ms: u64): vector<u8> {
    let mut id: vector<u8> = vector[];
    let mut i = 0u64;
    while (i < 8) {
        let shift = (((7 - i) * 8) as u8);
        id.push_back((((unlock_ms >> shift) & 0xFF) as u8));
        i = i + 1;
    };
    id.push_back(0u8);
    id
}

#[test]
fun after_unlock_succeeds() {
    let mut s = ts::begin(U);
    let mut c = clock::create_for_testing(s.ctx());
    c.set_for_testing(2000);
    timelock::seal_approve(id_for_unlock(1000), &c);
    c.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = 2)] // E_TOO_EARLY
fun before_unlock_aborts() {
    let mut s = ts::begin(U);
    let mut c = clock::create_for_testing(s.ctx());
    c.set_for_testing(500);
    timelock::seal_approve(id_for_unlock(1000), &c);
    c.destroy_for_testing();
    s.end();
}

// Conformance vector shared bit-for-bit with the client encoder
// (repos/seal-client/tests/conformance-vectors.json → timelock). unlock_ms = 1704067200000 must
// encode big-endian to 00 00 01 8c c2 51 f4 00. If the client's u64beBytes and this decode ever
// diverge (e.g. little-endian), one side's assertion fails.
#[test]
fun conformance_unlock_ms_big_endian_matches_vector() {
    let bytes = id_for_unlock(1704067200000);
    let expected: vector<u8> = vector[0x00, 0x00, 0x01, 0x8c, 0xc2, 0x51, 0xf4, 0x00];
    let mut i = 0u64;
    while (i < 8) {
        assert!(bytes[i] == expected[i], 100 + i);
        i = i + 1;
    };
    // And the on-chain decode accepts it exactly at the unlock instant.
    let mut s = ts::begin(U);
    let mut c = clock::create_for_testing(s.ctx());
    c.set_for_testing(1704067200000);
    timelock::seal_approve(bytes, &c);
    c.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = 1)] // E_BAD_ID
fun short_id_aborts() {
    let mut s = ts::begin(U);
    let c = clock::create_for_testing(s.ctx());
    timelock::seal_approve(vector[1u8, 2u8, 3u8], &c);
    c.destroy_for_testing();
    s.end();
}

// Boundary: unlock_ms = 0 (epoch) — any clock timestamp satisfies `>= 0` so this succeeds.
#[test]
fun unlock_ms_zero_succeeds() {
    let mut s = ts::begin(U);
    let mut c = clock::create_for_testing(s.ctx());
    c.set_for_testing(1000); // 1 second after epoch
    timelock::seal_approve(id_for_unlock(0), &c);
    c.destroy_for_testing();
    s.end();
}

// Boundary: unlock_ms = u64::MAX with clock set to u64::MAX — tests that big-endian decode
// of the maximum value does not overflow or wrap, and that `>= MAX` holds.
#[test]
fun unlock_ms_max_with_max_clock_succeeds() {
    let mut s = ts::begin(U);
    let mut c = clock::create_for_testing(s.ctx());
    let max_u64: u64 = 18446744073709551615u64;
    c.set_for_testing(max_u64);
    timelock::seal_approve(id_for_unlock(max_u64), &c);
    c.destroy_for_testing();
    s.end();
}

// Boundary: an id of exactly 8 bytes (minimum valid length) succeeds — no E_BAD_ID.
#[test]
fun exact_8_byte_id_succeeds() {
    let mut s = ts::begin(U);
    let mut c = clock::create_for_testing(s.ctx());
    c.set_for_testing(2000);
    // Exactly 8 bytes encoding unlock_ms = 1000.
    let id_8: vector<u8> = vector[0, 0, 0, 0, 0, 0, 3, 232]; // 1000 = 0x000003E8
    assert!(id_8.length() == 8, 500);
    timelock::seal_approve(id_8, &c);
    c.destroy_for_testing();
    s.end();
}
