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
sui move test        # 21 unit tests (nft_gate + timelock + sealed_content)
```

## Deployments

| Network | Package ID |
| --- | --- |
| testnet | `0x9f0563bfe42fbd29932cd280cc47efe17f5339b4dc569eb110114665eecc231e` (used by `seal-ui` and `seal-client` tests; `Published.toml`) |
| mainnet | — (pending) |

A second testnet deployment, `0x67520f80…88d3`, is recorded as `published-at` in `Move.toml`; which
of the two is canonical is an open question in [the audit](docs/audit/seal-policies-sui-audit.md).

## Dependency on `access-gate-sui`

`access_gate` is a **git dependency pinned to an immutable commit SHA** — Move packages are consumed
via git or local paths, never a package registry (there is no crates.io for Move). A tag is **not**
used because tags are mutable (`v0.0.1` has already been moved to a different commit):

```toml
[dependencies]
access_gate = { git = "https://github.com/meddleware-org/access-gate-sui.git", rev = "f191c2d338006c056d4ecfafa9bb0404afed37a5" }
```

That commit's manifest resolves `access_gate` to the canonical testnet package `0x0bedd0…`, which the
published `seal_policies` links against (the live access-gate objects are of that package's types).
Change the rev only together with the address it resolves to, and re-publish if that address changes.

## Deploy

Publish to testnet, then record the package id for the client (`VITE_SEAL_PACKAGE_ID_TESTNET`).
Because the on-chain address of `access_gate` is identical whether resolved via git or a local path,
a package already deployed (see Deployments above) does **not** need re-publishing after switching the
dependency form — only `Move.lock` changes.

## License

BSD Zero Clause License (`0BSD`). See [LICENSE](LICENSE).
