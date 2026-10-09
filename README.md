# seal_policies

Modular [Seal](https://seal-docs.wal.app/) access-control policies for Sui — the on-chain half of
Meddleware **Sealed Storage** (client-side encrypted, access-gated Walrus storage).

A Seal key server releases a decryption key share only if an on-chain `seal_approve*` function runs
without aborting (evaluated via `dry_run_transaction_block` under the requester's address). Each
policy type is a **self-contained module** exposing its own `seal_approve*` entry function. Adding a
policy is a new module — existing modules are never touched, and **no policy is privileged**.

Every `seal_approve*` and `sealed_content::publish` takes the shared **`config::PolicyConfig`** as
its second argument and aborts (`config::E_WRONG_VERSION`) unless it names this package version, so an
upgrade can retire older code everywhere at once (see [Version gating](#version-gating)).

## Modules

| Module | `seal_approve*` | Identity (`id`) layout | Gates on |
| --- | --- | --- | --- |
| `nft_gate` | `seal_approve`, `seal_approve_soulbound` | `[32-byte gate id][nonce]` | Ownership of a valid `access_gate` NFT/pass for that gate |
| `timelock` | `seal_approve` | `[8-byte big-endian unlock_ms][nonce]` | On-chain `Clock` ≥ unlock time |
| `sealed_content` | — (registry, not a policy) | — | Publishes `SealedContent` pointers binding a Walrus blob to a gate for discovery |
| `config` | — (version gate, not a policy) | — | Shared `PolicyConfig { version }`; `migrate` (needs `PolicyAdminCap`) |

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

### Version gating

Older package versions stay callable on-chain forever, so a key server could be asked to evaluate an
old, faulty `seal_approve*`. `config::init` shares one `PolicyConfig { version }` and gives the
`PolicyAdminCap` to the publisher. Each entry calls `config::check_version` first. An upgrade bumps
`VERSION`, then the cap holder calls `migrate` (forward only, `E_NOT_UPGRADE`), which retires every
older version at once. Seal identities stay under the original id, so content never needs re-sealing
for an upgrade. A new policy module must take `&PolicyConfig` and call `config::check_version` first.

### `sealed_content`

Not a Seal policy — an additive registry so `access_gate` operators can attach Seal-encrypted,
gate-unlockable content **without changing the access-gate contract**. `publish(policy, gate_id,
blob_id, seal_id, label)` shares a `SealedContent` and emits `SealedContentPublished` for discovery. The
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
sui move build --build-env testnet
sui move test --build-env testnet   # 37 unit tests (config + nft_gate + timelock + sealed_content)
```

## Deployments

| Network | Original id (types, events, Seal identity namespace) | Published-at (call targets) |
| --- | --- | --- |
| testnet | `0x0c8f73490b14836e6a7a724fb46b242cb061d04a5f193fd637159997f8a1773d` | `0x0c8f73490b14836e6a7a724fb46b242cb061d04a5f193fd637159997f8a1773d` (2026-10-09: links the 0.0.6 `access_gate`, `PolicyConfig` `0xee0403ba15c250223527150d147f29bedfb1ec46bb2282c341be462ff0ad7d1a`) |
| mainnet | — (pending) | — |

It links `access_gate` `0xd7ddaa94…`; `Published.toml` and `deployments.json` are the source of truth. Encrypt under the
original id and call `seal_approve` / `publish` at published-at.

Superseded: `0x61c4aaa4…7e42` (linked `access_gate` `0xa55789…`; before the 0.0.6 pass-kind rules; UpgradeCap burned) and `0x42cc181f851ef702c1fddc9b925553f03b71784edff49d80fbc260055f86d612` (original id; v2 published-at `0x8fcf9c…15cb`; linked `access_gate`
`0x1a81ca…`; predates version gating) and `0x9f0563bf…231e` (linked the pre-policy `access_gate` `0x0bedd0…`; UpgradeCap burned).
Strays `0x67520f80…88d3` and `0x882fcc68…e8cc` bundle their own copy of the `access_gate` module, so
their `nft_gate` can never accept a real gate's pass; their UpgradeCaps are burned (see
[the audit](docs/audit/seal-policies-sui-audit.md), F8).

## Dependency on `access-gate-sui`

`access_gate` is a **git dependency pinned to an immutable commit SHA** — Move packages are consumed
via git or local paths, never a package registry (there is no crates.io for Move). A tag is **not**
used because tags are mutable (`v0.0.1` has already been moved to a different commit):

```toml
[dependencies]
access_gate = { git = "https://github.com/meddleware-org/access-gate-sui.git", rev = "790695489fc4a7055cb31ce455c670af28f8f3c8" }
```

That commit records the testnet publication of `access_gate` `0xd7ddaa94…` (its `Published.toml`), which
the published `seal_policies` links against. Change the rev only together with the address it
resolves to, and re-publish if that address changes; after changing it, regenerate `Move.lock`
(`sui move build --build-env testnet`) and commit it.

## Deploy

`scripts/publish.sh <localnet|testnet|mainnet>` publishes a fresh package and records the package,
`UpgradeCap`, `PolicyAdminCap` and `PolicyConfig` in `.env.<network>` (gitignored), and the
`PolicyConfig` id with the custody record in `deployments.json` (committed, shipped in the npm package
for `@meddleware/seal-client`). Sui writes `Published.toml`. Commit both files after every publish.

## Custody and operations runbook

Every full release follows [CUSTODY.md](CUSTODY.md): publish, transfer the `PolicyAdminCap` and
`UpgradeCap` to the multisig, launch, verify during the planned window, then the multisig burns the
UpgradeCap on the planned date. Every script runs the same preflight as `access-gate-sui` (active env =
`NETWORK`, chain identifier, CLI major.minor vs `Published.toml` `toolchain-version`,
`MAINNET_CONFIRM=1` for mainnet; a skipped run exits `78`).

| Script | Effect | Dry run | Execute | Recovery |
| --- | --- | --- | --- | --- |
| `scripts/publish.sh <net>` | Fresh publish; records IDs and custody | — (publishing is the action) | as shown | The previous `.env.<net>` is kept as `.env.<net>.<timestamp>.bak`; never re-publish to recover a later step. `ALLOW_TOOLCHAIN_CHANGE=1` permits a deliberate move to a new CLI version |
| `scripts/transfer-authority.sh [--include-upgrade-cap]` | Move the `PolicyAdminCap` (and the UpgradeCap) to the multisig | `NETWORK=<net> MULTISIG_ADDRESS=0x… bash scripts/transfer-authority.sh --include-upgrade-cap` | `DRY_RUN=0 …` then `YES` | Each object is re-verified (type, package, owner); a re-run refuses anything already transferred. Records the multisig in `deployments.json` |
| `scripts/make-immutable.sh` | Burn the UpgradeCap on the planned date. The deploy key burns directly; a multisig-owned cap gets an unsigned transaction and the signing steps | `NETWORK=<net> bash scripts/make-immutable.sh` | `DRY_RUN=0 …` then `YES` (direct), or sign and execute the written transaction (multisig) | Irreversible. Checks the cap's type and package first and that it is gone afterwards; records the burn in `deployments.json` |
| `scripts/multisig-address.sh` | Derive the custody multisig address | `MULTISIG_PKS=… MULTISIG_WEIGHTS=… MULTISIG_THRESHOLD=… bash scripts/multisig-address.sh` | — (read-only) | — |

Until the UpgradeCap is burned, its holder can upgrade `seal_policies` and thereby change who can
decrypt existing ciphertexts (the Seal identity namespace is the package).

## License

BSD Zero Clause License (`0BSD`). See [LICENSE](LICENSE).
