# BitV Testnet Asset Strategy (Build 10, decided in Build 11)

No token address is fabricated in this document. As of Build 10, no
real, independently-verified Monad Testnet asset address was confirmed
anywhere in this repository. In Build 11, the BitV team explicitly
decided **Path A** below (BitV-deployed test tokens) rather than
continue waiting on a real asset — see
`contracts/src/testing/BitVTestToken.sol` and
`contracts/script/DeployTestnetAssets.s.sol`, not yet broadcast to
Monad Testnet.

## What the MVP smoke test actually needs

Per `docs/testnet-smoke-test.md`, exercising the full protocol end to
end needs, at minimum:

1. **One lending-pool asset** (deposit/withdraw liquidity, deposit
   collateral, borrow, repay, liquidate) — the smoke test can use a
   single asset as both collateral and debt asset if only one is
   available, or two if a second is added.
2. **One yield-vault underlying asset** (can be the same asset as #1 —
   nothing requires it to be different).
3. **One RWA-registered asset** (can also reuse #1/#2's underlying — RWA
   registration is a registry entry pointing at an existing pool asset,
   not a separate token requirement, per
   `BitVRWACollateralRegistry.registerAsset`'s existing design).

So the smoke test's *minimum* real requirement is **one** ERC-20 asset;
a second is useful for exercising liquidation/borrow-against-different-
collateral paths but not required to prove the core mechanics work.

## Asset table

| Symbol | Decimals | Address | Source | Verified? | Suitable for Monad Testnet? | Real or test token? |
|---|---|---|---|---|---|---|
| — | — | — | — | No | N/A | No real asset is confirmed |

No row is filled in with a real address. Filling this table with a
guessed or unverified address would violate this milestone's explicit
"do not fabricate addresses" instruction.

## The two realistic paths forward

### Path A — BitV deploys its own test tokens (recommended for the first smoke test)

Deploy a small number of plain ERC-20 test tokens directly (mirroring
`contracts/test/mocks/MockERC20.sol`'s pattern, but as a clearly-labeled,
separate, non-mock production-path contract if this is done for real —
**not** by deploying the actual `contracts/test/mocks/` file itself,
which stays test-only per `docs/deployment-readiness.md`'s inventory).

- **Pros:** no dependency on finding/verifying a third party's testnet
  token; BitV controls supply/minting for test wallets; zero risk of
  accidentally treating a real asset's testnet deployment as
  meaningful.
- **Cons:** these tokens have no independent value or recognition —
  fine for exercising mechanics, useless as a demonstration of "real"
  asset support.
- **Explicit labeling requirement:** any such token must be labeled a
  test token everywhere it's referenced (contract name, dashboard,
  documentation) — never presented as, or confused with, a CVA or any
  asset with real backing. This mirrors the existing
  `TestYieldStrategy`/`isTestStrategy` labeling discipline.

### Path B — source a real, confirmed Monad Testnet asset address

Would require independently verifying a specific token's deployment
address on Monad Testnet from a primary source (the token issuer's own
documentation, or a reputable, currently-accurate testnet asset
registry) — **not done by this milestone**, since no such verification
was performed and guessing would violate the "do not fabricate
addresses" instruction. If pursued later, the verification must be
documented here with its source before the address is used anywhere in
`services/contracts/addresses.ts` or a `Deploy.s.sol` run.

## CVA labeling

**No token in this document is labeled a CVA.** Per this milestone's
explicit instruction, no token may be labeled CVA unless Cleanverse
officially confirms it — and Cleanverse has not confirmed any token as a
CVA in this project's history (see `docs/cleanverse-dependency-lock.md`).
This applies equally to test tokens deployed under Path A: a BitV-issued
test token is never a CVA regardless of how it's configured in
`BitVRWACollateralRegistry`.

## Decision for this milestone

**Blocker, not resolved:** no real testnet asset address is confirmed.
Recorded here as an explicit blocker per this milestone's instruction
("If no reliable testnet assets are currently available, create a clear
deployment blocker instead of inventing them"). Recommended next step:
Path A (BitV-deployed test tokens), decided and executed as a deliberate
choice in a future build — not invented here.
