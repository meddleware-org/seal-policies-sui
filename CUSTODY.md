# Custody — seal_policies

Who holds this package's authority objects, and how that changes over a release. The scripts named
here all run the same preflight (active env, chain identifier, CLI version, `MAINNET_CONFIRM=1` on
mainnet), are dry runs by default, and ask for a typed confirmation before anything irreversible.

While the `UpgradeCap` exists, an upgrade can change `seal_approve*` and so change who can decrypt
every ciphertext sealed under this package. That is why the cap moves to a multisig straight after
publishing and is burned at the end of the verification window.

## Authority objects

| Object | Created by | Controls | Long-term holder |
| --- | --- | --- | --- |
| `UpgradeCap` | publish | replacing the package code (every policy) | the multisig, until it burns the cap on the planned date |
| `PolicyAdminCap` | `config::init` | `config::migrate` (retiring older package versions) | the multisig, permanently |

`PolicyConfig` is the shared version object every policy reads; it has no owner.

## Release lifecycle (every full release)

1. **Publish** from the deploy key: `scripts/publish.sh <network>`. It records the package, both caps
   and `PolicyConfig` in `.env.<network>`, and `policyConfigId` plus `custody.upgradeCapOwner` (the
   deploy key) in `deployments.json`. `access_gate` must already be published at the commit
   `Move.toml` pins.
2. **Transfer** to the multisig:
   `DRY_RUN=0 NETWORK=<network> MULTISIG_ADDRESS=0x… bash scripts/transfer-authority.sh --include-upgrade-cap`.
   Each object is re-read on-chain (exact type, this package, owned by the deploy key) before it is
   sent; `deployments.json` then records the multisig.
3. **Set the burn date.** Write `custody.plannedBurnDate` (`YYYY-MM-DD`) in `deployments.json` and
   commit it.
4. **Launch and verify.** While the multisig holds the UpgradeCap, a defect found in this window can
   be fixed with an upgrade, and `migrate` retires the faulty version for every key server at once.
5. **Burn** on the planned date: `NETWORK=<network> DRY_RUN=0 bash scripts/make-immutable.sh` writes
   the unsigned `0x2::package::make_immutable` transaction with the multisig as sender and prints the
   signing steps. Afterwards record `custody.upgradeCapOwner: null` and `custody.burnedAt`.

## The multisig

The same multisig as `access_gate` (see that repository's `CUSTODY.md`). Derive it with
`scripts/multisig-address.sh` from the members' `publicBase64Key` values, weights and threshold, and keep
those values with the address. It must hold a little SUI for gas.

## Signing a transaction as the multisig

1. `sui client ptb --move-call <target> <args…> --sender @<multisig> --gas-budget 100000000 --serialize-unsigned-transaction > tx.b64`
2. Each signer: `sui keytool sign --address <signer> --data "$(cat tx.b64)" --json` → `suiSignature`.
3. `sui keytool multi-sig-combine-partial-sig --pks <pk…> --weights <w…> --threshold <t> --sigs <suiSignature…> --json`
   → `multisigSerialized`.
4. `sui client execute-signed-tx --tx-bytes "$(cat tx.b64)" --signatures <multisigSerialized>`.

## Upgrading during the verification window

1. Bump `VERSION` in `sources/config.move` and make the change (struct layouts and `entry`
   signatures used by key servers stay compatible, or the change ships as a fresh package).
2. `sui client upgrade --upgrade-capability <cap> --sender <multisig> --serialize-unsigned-transaction`,
   signed as above.
3. Call `config::migrate(&PolicyAdminCap, &mut PolicyConfig)` from the multisig. Every older version's
   `seal_approve*` and `publish` now abort with `config::E_WRONG_VERSION`.
4. Release the npm package and `@meddleware/seal-client` with the new `published-at`. Identities stay
   under the original id, so sealed content needs no re-sealing.

## Rehearsal

Rehearsed on localnet on 2026-10-02: `publish.sh localnet` (which also publishes `access_gate`), the
timelock policy approved and refused on-chain against the new `PolicyConfig`, transfer of both caps to
a 1-of-2 multisig, then a burn signed by one member and executed with `execute-signed-tx`.
