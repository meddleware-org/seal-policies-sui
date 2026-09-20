# CLAUDE.md — seal_policies (Move)

## What this package is

The **on-chain half of Sealed Storage**: modular [Seal](https://seal-docs.wal.app/) access-control
policies for Sui. A Seal key server releases a decryption key share only if an on-chain
`seal_approve*` function runs without aborting (evaluated via `dry_run_transaction_block` under the
requester's address). Its client counterpart is
[`@meddleware/seal-client`](https://github.com/meddleware-org/seal-client) — each Move module here
mirrors one client provider 1:1.

## Architectural invariants

- **One module per policy; no module is privileged.** Each policy is self-contained and exposes its
  own `seal_approve*` entry function. Adding a policy is a **new module** — existing modules are
  never edited. This is the same peer-provider discipline as the client registry.
- **`seal_approve*` must be side-effect free.** It is dry-run, not executed. It may only read/assert.
  Consequently a single-use `nft_gate` pass acts as **membership** (not consumed per decrypt); an
  exhausted (zero-use) pass is rejected.
- **Identity is namespaced, and the layout must match the client bit-for-bit.** `nft_gate` asserts
  the identity's first 32 bytes equal the gate object id (a pass for gate A cannot decrypt gate B's
  content); `timelock` decodes `[8-byte BE unlock_ms][nonce]`. These layouts are the mirror of
  `seal-client`'s `bytes.ts`/providers — never change one side alone.
- **Ownership is enforced by Seal, not re-implemented here.** The key server dry-runs under the
  requester's address, so a non-owned object fails input resolution before `seal_approve` logic runs.
- **`nft_gate` reuses `access_gate` unmodified.** It depends on the `access_gate` primitive (via
  `is_valid_for`) without changing it. `sealed_content` is an **additive** discovery registry, also
  without touching `access_gate`.
- **Move deps are git/local, never a registry.** `access_gate` is a git dependency pinned to a tag
  (`rev = "v0.0.2"`); that tag must exist on GitHub before this package builds. See the README's
  dependency + publishing-order notes.

## Layout

| Path | Purpose |
| --- | --- |
| `sources/nft_gate.move` | `seal_approve` / `seal_approve_soulbound` — gate-pass membership policy. |
| `sources/timelock.move` | `seal_approve` — Clock-based time-lock (`0x6`). |
| `sources/sealed_content.move` | `publish(...)` + `SealedContentPublished` event — discovery pointers (not a policy). |
| `tests/*` | 8 unit tests (nft_gate + timelock). Run `sui move test`. |
| `Move.toml` / `Published.toml` | Package manifest + recorded publish. |

The full module/identity/roadmap tables live in [README.md](README.md) — keep the two in sync.

## What NOT to do

- Do not add side effects to any `seal_approve*` (it is dry-run only).
- Do not edit an existing policy module to add a new policy — write a new module.
- Do not change an identity layout without changing the matching `seal-client` provider.
- Do not modify `access_gate` from here; `nft_gate`/`sealed_content` are strictly additive.

---

## Deferred documentation — NOT for the `docs.` website (planned here per Part 0.4)

> Captured for the future **`dev.meddleware.co.uk`** subdomain and white-label offering; excluded
> from the user-facing `docs.` site.

### `dev.` — developer/integrator (to write later)

- **Policy authoring guide:** the module contract (`seal_approve*` shape, side-effect-free rule,
  identity namespacing) paired with the client provider that mirrors it; the identity-layout match as
  the primary footgun. The README's **Future policy roadmap** (allowlist, subscription, owner-only,
  token/balance, kiosk/royalty, DAO/multisig, epoch/vesting, password) is the backlog to anchor to a
  timeline later.
- **Reference tables (curated from source — Move has no clean autodoc):** per-module `seal_approve*`
  signatures, identity layouts, and the `SealedContentPublished` event schema. These feed the docs
  site's Sealed Storage reference and the `dev.` deep-dive alike.
- **Deploy runbook:** build/test/publish, the `access_gate` git-tag prerequisite + publishing order,
  and recording `VITE_SEAL_PACKAGE_ID_{NET}` for the client.

### White-label (to write later)

- Operators publishing their **own `seal_policies`** (own package id + key-server committee) and
  choosing which policy modules to ship; how that maps to the client's provider set.
