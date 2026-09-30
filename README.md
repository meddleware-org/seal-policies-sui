# seal_policies

Modular [Seal](https://seal-docs.wal.app/) access-control policies for Sui — the on-chain half of
Meddleware **Sealed Storage** (client-side encrypted, access-gated Walrus storage).

A Seal key server releases a decryption key share only if an on-chain `seal_approve*` function runs
without aborting (evaluated via `dry_run_transaction_block` under the requester's address). Each
policy type is a **self-contained module** exposing its own `seal_approve*` entry function. Adding a
policy is a new module — existing modules are never touched, and **no policy is privileged**.

## Modules

| Module | `seal_approve*` | Identity (`id`) layout | Gates on |
| --- | --- | --- | --- |
| `nft_gate` | `seal_approve`, `seal_approve_soulbound` | `[32-byte gate id][nonce]` | Ownership of a valid `access_gate` NFT/pass for that gate |
| `timelock` | `seal_approve` | `[8-byte big-endian unlock_ms][nonce]` | On-chain `Clock` ≥ unlock time |
| `sealed_content` | — (registry, not a policy) | — | Publishes `SealedContent` pointers binding a Walrus blob to a gate for discovery |

### `nft_gate`

Reuses the [`access_gate`](../access-gate-sui) primitive **without modifying it**. `seal_approve`
asserts (1) the identity is namespaced to the gate — its first 32 bytes equal the gate object id, so
a pass for gate A cannot decrypt content sealed for gate B — and (2) `access_gate::is_valid_for`
(the pass was minted from that gate). Ownership is enforced by Seal itself: the key server dry-runs
under the requester's address, so a non-owned NFT fails input validation before this runs.

Because `seal_approve` must be side-effect free, a single-use pass acts as **membership** (it is not
consumed per decrypt); an already-exhausted (zero-use) pass is rejected. If the gate's immutable
`access_gate` policy has `pause_blocks_decryption`, a paused gate also denies decryption
(`E_GATE_PAUSED = 4`) until it is unpaused; otherwise pausing only stops purchases.

### `timelock`

Time-lock encryption. Shares nothing with `nft_gate` (no gate, no NFT) — it exists to keep the
abstraction honest: adding a policy is a new module, not a change to an existing one.

### `sealed_content`

Not a Seal policy — an additive registry so `access_gate` operators can attach Seal-encrypted,
gate-unlockable content **without changing the access-gate contract**. `publish(gate_id, blob_id,
seal_id, label)` shares a `SealedContent` and emits `SealedContentPublished` for discovery. The
pointers are public; confidentiality is enforced by Seal + `nft_gate`.

## Future policy roadmap (drop-in — a module here + a client provider)

Not yet implemented; documented so a later version-anchored timeline can pick them up. Each is a new
module with its own `seal_approve*`; none changes the existing modules:

- **allowlist** — shared `Allowlist` of addresses; `seal_approve(id, allowlist)` checks
  `ctx.sender()` membership (admin add/remove).
- **subscription** — time-bound `Subscription` (owned by sender) for a `Service`; validity vs `Clock`.
- **owner-only** — id encodes an address; only that address decrypts (no extra objects).
- **token / balance gate** — require a minimum `Coin<T>` balance or a specific staked position.
- **kiosk / royalty** — gate on holding an item in a Kiosk or paying a royalty.
- **DAO / multisig / role** — gate on membership of a governance object or a capability.
- **epoch / vesting** — gate on `ctx.epoch()` ≥ target, or a vesting schedule.
- **password / committed-secret** — gate on a hash preimage committed on-chain.

## Build & test

```bash
sui move build
sui move test        # 24 unit tests (nft_gate + timelock + sealed_content)
```

## Deployments

| Network | Package ID |
| --- | --- |
| testnet | `0x42cc181f851ef702c1fddc9b925553f03b71784edff49d80fbc260055f86d612` (links `access_gate` `0x1a81ca…`; `Published.toml`) |
| mainnet | — (pending) |

Superseded: `0x9f0563bf…231e` (linked the pre-policy `access_gate` `0x0bedd0…`; UpgradeCap burned).
Strays `0x67520f80…88d3` and `0x882fcc68…e8cc` bundle their own copy of the `access_gate` module, so
their `nft_gate` can never accept a real gate's pass; their UpgradeCaps are burned (see
[the audit](docs/audit/seal-policies-sui-audit.md), F8).

## Dependency on `access-gate-sui`

`access_gate` is a **git dependency pinned to an immutable commit SHA** — Move packages are consumed
via git or local paths, never a package registry (there is no crates.io for Move). A tag is **not**
used because tags are mutable (`v0.0.1` has already been moved to a different commit):

```toml
[dependencies]
access_gate = { git = "https://github.com/meddleware-org/access-gate-sui.git", rev = "dcd2d3c2f918904950e8cb079d0c648fc79475f3" }
```

That commit records the testnet publication of `access_gate` `0x1a81ca…` (its `Published.toml`), which
the published `seal_policies` links against. Change the rev only together with the address it
resolves to, and re-publish if that address changes; after changing it, regenerate `Move.lock`
(`sui move build --build-env testnet`) and commit it.

## Deploy

Publish to testnet, then record the package id for the client (`VITE_SEAL_PACKAGE_ID_TESTNET`).
Because the on-chain address of `access_gate` is identical whether resolved via git or a local path,
a package already deployed (see Deployments above) does **not** need re-publishing after switching the
dependency form — only `Move.lock` changes.

## Operations runbook (UpgradeCap custody)

Pick **one** custody option per network. Both scripts are dry-run by default, verify that the cap
is this package's UpgradeCap owned by the active address, and run the same preflight as
`access-gate-sui` (active env = `NETWORK`, chain identifier, CLI major.minor vs `Published.toml`
`toolchain-version`, `MAINNET_CONFIRM=1` for mainnet; a skipped run exits `78`).

| Script | Effect | Dry run | Execute | Recovery |
| --- | --- | --- | --- | --- |
| `scripts/make-immutable.sh` | Burn the UpgradeCap: the policy package can never change (future changes ship as a new package) | `NETWORK=testnet bash scripts/make-immutable.sh` | `DRY_RUN=0 …` then `YES` | Irreversible. The script checks afterwards that the cap is gone; remove `upgrade-capability` from `Published.toml` |
| `scripts/transfer-upgrade-cap.sh` | Move the UpgradeCap to a multisig (upgrades need M-of-N) | `NETWORK=testnet MULTISIG_ADDRESS=0x… bash scripts/transfer-upgrade-cap.sh` | `DRY_RUN=0 …` then `YES` | Record the multisig as the cap owner; a re-run refuses once the active address no longer owns the cap |

Until a custody option is executed, the deploy key can upgrade `seal_policies` and thereby change
who can decrypt existing ciphertexts (the Seal identity namespace is the package).

## License

BSD Zero Clause License (`0BSD`). See [LICENSE](LICENSE).
