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
consumed per decrypt); an already-exhausted (zero-use) pass is rejected.

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
sui move test        # 8 unit tests (nft_gate + timelock)
```

## Deployments

| Network | Package ID |
| --- | --- |
| testnet | `0x9f0563bfe42fbd29932cd280cc47efe17f5339b4dc569eb110114665eecc231e` |
| mainnet | — (pending) |

## Dependency on `access-gate-sui`

`access_gate` is a **git dependency pinned to a tag** — Move packages are consumed via git or local
paths, never a package registry (there is no crates.io for Move):

```toml
[dependencies]
access_gate = { git = "https://github.com/meddleware-org/access-gate-sui.git", rev = "v0.0.2" }
```

`access-gate-sui`'s own `published-at` resolves `access_gate` to its on-chain address, so no address
override is needed here. **Publishing order matters:** the `access-gate-sui` `v0.0.2` tag must exist
on GitHub before this package builds — the git dependency is fetched at that rev.

## Deploy

Publish to testnet, then record the package id for the client (`VITE_SEAL_PACKAGE_ID_TESTNET`).
Because the on-chain address of `access_gate` is identical whether resolved via git or a local path,
a package already deployed (see Deployments above) does **not** need re-publishing after switching the
dependency form — only `Move.lock` changes.

## License

BSD Zero Clause License (`0BSD`). See [LICENSE](LICENSE).
