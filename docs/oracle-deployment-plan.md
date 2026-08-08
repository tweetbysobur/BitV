# BitV Oracle Deployment Plan (Build 10)

No external oracle integration is added by this milestone — no address
or interface beyond what's already in this repository is verified enough
to wire in. This document separates what a testnet demo can use safely
from what production requires, and states the gap plainly rather than
papering over it.

## What oracle data the protocol actually needs

`IPriceOracle.getPrice(address asset) returns (uint256 price, uint8 decimals)`
is the entire interface every consumer below relies on — a single
synchronous price read, no round ID, no timestamp, no confidence
interval.

| Consumer | What it needs the oracle for | What happens if the oracle reverts / is unset | What happens on a zero price |
|---|---|---|---|
| `BitVPoolManager` | Stores `priceOracle` per pool (`createPool`/`setPriceOracle`); does not call it itself | N/A — it only stores the address | N/A |
| `BitVLendingManager` — collateral valuation | `_accountData`'s aggregation loop calls `_tryValueOf` per collateral asset | Asset is skipped from `totalCollateralValue` (pool with no oracle configured is already skipped via `pool.priceOracle == address(0)` check) | Asset is skipped from `totalCollateralValue` — same as "no oracle," a documented existing limitation |
| `BitVLendingManager` — debt valuation | Same aggregation loop, per debt asset | Same as above | Same as above — **notably, this understates risk**: a debt asset that goes to a zero/broken price silently drops out of `totalDebtValue`, which can make a genuinely under-collateralized position appear healthier than it is (see `docs/economic-engine-review.md`, already documented, not changed this milestone) |
| `BitVLendingManager` — `borrow()`'s direct value check | `_valueOf` (reverting variant) on the specific asset being borrowed | N/A — pool with no oracle already reverts earlier (`PriceOracleNotSet`) | Reverts (`ProtocolErrors.ZeroPrice`) — the one place a zero price is *not* silently skipped, since this is a single-asset check on the caller's own current action, not a cross-asset aggregation |
| `BitVLendingManager` — `liquidate()`'s repay/seize conversion | `_valueOf`/`_amountFromValue` on the specific debt/collateral assets involved | Reverts (`PriceOracleNotSet`) | Reverts (`ProtocolErrors.ZeroPrice`) |
| `KinkedInterestRateModel` | Does not call `IPriceOracle` at all — rates are a pure function of supplied/borrowed underlying amounts | N/A | N/A |
| `BitVRWACollateralRegistry` | `isEligibleForNewActivity` reads the asset's own configured oracle directly; `markPriceFresh` reads it to stamp a freshness attestation | `isEligibleForNewActivity` returns `false` (fails safe); `markPriceFresh` reverts (`InvalidOraclePrice` semantics via the same zero-price check) | Same — a live zero price is never treated as eligible, independent of the staleness timestamp |

**Liquidation and health-factor math never call the oracle directly** —
they consume the already-aggregated `totalCollateralValue`/
`totalDebtValue`/`weightedLiqThresholdValue` figures `_accountData`
computes from the per-asset oracle reads above. There is no separate
"liquidation oracle" or "health-factor oracle."

## Freshness / staleness

`IPriceOracle` itself carries **no timestamp or round data** — this is a
protocol-level gap outside the RWA registry's own layer. Only
`BitVRWACollateralRegistry` has any staleness protection
(`maxOracleStalenessSeconds` + `markPriceFresh`'s attestation timestamp,
per `docs/rwa-market-specification.md` §8). Ordinary (non-RWA) pool
collateral/debt pricing via `BitVLendingManager` has no staleness check
at all — a stale-but-nonzero price is used exactly as read, with no
warning. This is an existing, documented characteristic of the protocol
(see `docs/economic-engine-review.md`), not something this milestone
changes or newly discovers.

## TESTNET ORACLE

`StaticPriceOracle` (`contracts/src/oracles/StaticPriceOracle.sol`) —
already implemented, admin-set prices via `setPrice(asset, price,
decimals)`, `Ownable`-gated.

**Acceptable use:** a controlled testnet/local smoke test, run by the
BitV team, where the team itself is the only party relying on the
prices, no external user is expected to trust them, and this is
disclosed everywhere the deployment is referenced (dashboard, any public
testnet announcement). This is exactly the "controlled local/testnet
testing" case Build 10's brief allows.

**Limitations that must stay documented wherever this is used, not
just here:**
- The `Ownable` owner can single-handedly set any price for any asset,
  at any time — this directly controls who gets liquidated and at what
  rate. There is no on-chain constraint preventing an obviously
  manipulative price.
- No staleness protection for ordinary lending pools (see above) — a
  price set once and never updated is used forever, silently, for
  anything other than RWA-registered assets.
- No aggregation, no external data source, no economic security
  whatsoever — it is a manually-typed number in storage.
- **Never deploy this as a production oracle. Never let a testnet
  deployment using it be mistaken for a production-ready protocol** —
  the dashboard (Build 08) and any deployment documentation must keep
  this disclosed, matching the existing "test/non-production strategy"
  labeling discipline already established for `TestYieldStrategy`.

## PRODUCTION ORACLE

**No production-suitable oracle exists in this codebase, and none is
selected by this milestone.** Building or integrating one is explicitly
out of this audit's scope (Build 10's stop condition: "Do not add an
external oracle integration unless its address and interface are
verified" — no such address/interface has been verified for Monad
Testnet). This is a **hard deployment blocker for anything holding real
value**, tracked here rather than silently worked around:

- A production oracle needs, at minimum: a decentralized or otherwise
  economically-secured price source (not a single admin-set value),
  on-chain freshness/staleness enforcement usable by
  `BitVLendingManager` directly (not just the RWA registry's own
  attestation layer), and a confirmed, audited deployment address on
  Monad Testnet (and eventually mainnet).
- Whether any established oracle provider (Chainlink, Pyth, or a
  Monad-native provider) has a confirmed deployment on Monad Testnet is
  **not verified by this milestone** — this document does not name one,
  because doing so without verification would be exactly the "invent an
  oracle address" behavior this milestone is instructed not to do.
- **Action for Build 11 or later:** research and confirm (from a
  primary source, not inference) which oracle providers, if any, have a
  verified deployment on Monad Testnet, then design the
  `IPriceOracle`-conforming adapter for the one selected. Until that
  research happens, this remains an open, explicitly-flagged blocker.

## Decision for this milestone

Testnet smoke-testing (per `docs/testnet-smoke-test.md`) may proceed
using `StaticPriceOracle`, with the limitations above disclosed
everywhere it's referenced. No production deployment may proceed without
first resolving the production-oracle gap documented here.
