// SPDX-License-Identifier: 0BSD

// Abort codes by literal (see config.move): E_WRONG_VERSION = 1, E_NOT_UPGRADE = 2.
#[test_only]
module seal_policies::config_tests;

use seal_policies::config::{Self, PolicyConfig, PolicyAdminCap};
use sui::test_scenario as ts;

const ADMIN: address = @0xA1;

#[test]
fun init_shares_current_version_and_gives_cap_to_sender() {
    let mut s = ts::begin(ADMIN);
    config::init_for_testing(s.ctx());
    s.next_tx(ADMIN);
    let policy = s.take_shared<PolicyConfig>();
    assert!(policy.version() == config::package_version(), 0);
    assert!(config::package_version() == 1, 1);
    let cap = s.take_from_sender<PolicyAdminCap>();
    s.return_to_sender(cap);
    ts::return_shared(policy);
    s.end();
}

#[test]
fun migrate_moves_an_older_config_forward() {
    let mut s = ts::begin(ADMIN);
    config::init_for_testing(s.ctx());
    s.next_tx(ADMIN);
    let mut policy = s.take_shared<PolicyConfig>();
    let cap = s.take_from_sender<PolicyAdminCap>();
    config::set_version_for_testing(&mut policy, 0);
    config::migrate(&cap, &mut policy);
    assert!(policy.version() == config::package_version(), 0);
    let effects = s.next_tx(ADMIN);
    assert!(effects.num_user_events() == 1, 1); // PolicyConfigMigratedEvent
    s.return_to_sender(cap);
    ts::return_shared(policy);
    s.end();
}

#[test]
#[expected_failure(abort_code = 2, location = seal_policies::config)] // E_NOT_UPGRADE
fun migrate_at_current_version_aborts() {
    let mut s = ts::begin(ADMIN);
    config::init_for_testing(s.ctx());
    s.next_tx(ADMIN);
    let mut policy = s.take_shared<PolicyConfig>();
    let cap = s.take_from_sender<PolicyAdminCap>();
    config::migrate(&cap, &mut policy);
    s.return_to_sender(cap);
    ts::return_shared(policy);
    s.end();
}

#[test]
#[expected_failure(abort_code = 2, location = seal_policies::config)] // E_NOT_UPGRADE
fun migrate_never_moves_backwards() {
    let mut s = ts::begin(ADMIN);
    config::init_for_testing(s.ctx());
    s.next_tx(ADMIN);
    let mut policy = s.take_shared<PolicyConfig>();
    let cap = s.take_from_sender<PolicyAdminCap>();
    config::set_version_for_testing(&mut policy, config::package_version() + 1);
    config::migrate(&cap, &mut policy);
    s.return_to_sender(cap);
    ts::return_shared(policy);
    s.end();
}
