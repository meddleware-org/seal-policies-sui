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

#[test]
#[expected_failure(abort_code = 1)] // E_BAD_ID
fun short_id_aborts() {
    let mut s = ts::begin(U);
    let c = clock::create_for_testing(s.ctx());
    timelock::seal_approve(vector[1u8, 2u8, 3u8], &c);
    c.destroy_for_testing();
    s.end();
}
