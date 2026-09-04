// SPDX-License-Identifier: 0BSD

/// Seal access policy — time-lock encryption (TLE).
///
/// Decryption is permitted once the on-chain `Clock` passes an unlock timestamp encoded in the
/// first 8 bytes of the identity (big-endian milliseconds). This policy deliberately shares
/// NOTHING with `nft_gate` (no gate, no NFT, different argument shape) — it exists to keep the
/// policy abstraction honest: adding a policy type is a new module, not a change to existing
/// ones, and nothing privileges the NFT-gate case.
module seal_policies::timelock;

use sui::clock::Clock;

/// Identity too short to carry an 8-byte unlock timestamp.
const E_BAD_ID: u64 = 1;
/// The unlock time has not yet passed.
const E_TOO_EARLY: u64 = 2;

/// Seal approval: succeeds once `clock.timestamp_ms() >= unlock_ms`, where `unlock_ms` is the
/// big-endian `u64` in the first 8 bytes of `id`. Any suffix bytes are ignored (they let the
/// caller make each ciphertext's identity unique).
entry fun seal_approve(id: vector<u8>, clock: &Clock) {
    assert!(id.length() >= 8, E_BAD_ID);
    let mut unlock_ms: u64 = 0;
    let mut i = 0;
    while (i < 8) {
        unlock_ms = (unlock_ms << 8) | (id[i] as u64);
        i = i + 1;
    };
    assert!(clock.timestamp_ms() >= unlock_ms, E_TOO_EARLY);
}
