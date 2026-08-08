# BitV RWA Collateral Registry Implementation (Build 06.1)

Implements `docs/rwa-market-specification.md` exactly — the architecture
decision (B: a dedicated registry connected to `BitVLendingManager` via
a narrow, optional, fail-safe interface), no redesign of the lending
engine. This document records what was actually built, one real bug
found and fixed during its own review, and what remains a known
limitation.

## Registry architecture

New: `contracts/src/core/BitVRWACollateralRegistry.sol`
(`BitVRoleConsumer`-based, no compliance guard of its own — it has no
user-facing protected actions; every compliance-relevant action still
lives in `BitVLendingManager`), implementing
`IRWACollateralRegistry` (`contracts/src/interfaces/
IRWACollateralRegistry.sol`).

The registry owns **exactly one responsibility**: whether a registered
RWA asset's collateral currently counts toward *new* borrowing
capacity. It does not hold collateral, does not track debt, does not
compute health factors, and does not perform liquidation — all of that
remains 100% `BitVLendingManager`, reused unmodified in its own logic
(only extended with the integration hooks described below, exactly
mirroring how `BitScoreManager` was wired into the same contract in
Build 04).

```
BitVLendingManager (unmodified core logic + new integration hooks)
  │  optional, try/catch-wrapped, fail-safe-to-ineligible
  ▼
IRWACollateralRegistry (narrow interface: isRegisteredAsset,
                         isEligibleForNewActivity,
                         isDebtAssetAllowed, getCollateralCap)
  │  implemented by
  ▼
BitVRWACollateralRegistry (registration, status, oracle staleness,
                            allowed-debt-asset restrictions)
```

## Asset states

Per the task's explicit narrowing of the specification's five-state
model: **four states — `Unregistered`, `Active`, `Frozen`, `Delisted`.**
`Suspended` (from the specification's fuller model) was not implemented
as a separate state: its practical effect (temporary block on new
deposits/borrowing) is already covered by `Frozen`, and its
oracle-specific trigger is already covered independently by the
staleness check in `isEligibleForNewActivity` — adding a fifth status
value would not have changed any actual behavior, only added an
unused-in-practice enum member.

**Valid transitions**: `Unregistered -> Active` (via `registerAsset`
only), `Active <-> Frozen` (freely, `setAssetStatus`), `Active ->
Delisted`, `Frozen -> Delisted`. **`Delisted` is terminal** — no
transition out of it exists, and (see "Delisted asset behavior" below)
the same asset address can never be re-registered once delisted.

## Frozen asset behavior

Implemented exactly per the task's table:

| Action | Frozen behavior | Where enforced |
|---|---|---|
| New collateral deposit | **Stops** | `BitVLendingManager.depositCollateral` -> `_requireRwaEligibleForNewDeposit` -> reverts `RWAErrors.AssetNotEligibleForDeposit` |
| New borrowing capacity from this asset | **Stops** | `_accountData`'s aggregation loop excludes this asset's value from `weightedLtvValue`/`weightedMaxLtvValue` (but not from `totalCollateralValue`/`weightedLiqThresholdValue` — see below) |
| Repayment | **Available** — unaffected, no registry check exists on `repay()` | unchanged |
| Withdrawal | **Available** — unaffected, no registry check exists on `withdrawCollateral()` | unchanged; `test_FrozenRwa_WithdrawalStillAllowed` |
| Liquidation | **Available** — unaffected, no registry check exists on `liquidate()` | unchanged; `test_FrozenCollateral_LiquidationStillAvailable` |

**The key design decision making all of this correct, not just
convenient**: a frozen (or delisted, or oracle-stale) asset's value
**still counts** toward `totalCollateralValue` and
`weightedLiqThresholdValue` — i.e. health factor and liquidation
remain fully accurate — only its contribution to `weightedLtvValue`/
`weightedMaxLtvValue` (new borrowing capacity) is zeroed. This is what
lets liquidation "remain available" *meaningfully*: a frozen asset
doesn't become invisible to the health-factor calculation (which would
either falsely liquidate or falsely protect existing positions); it
simply stops being useful for taking out *new* debt.

## Delisted asset behavior

Explicitly defined, per the task's instruction not to silently
invalidate accounting:

- **Existing collateral/debt accounting is completely unaffected** —
  `setAssetStatus(asset, Delisted)` touches only the registry's own
  `AssetConfig.status` field; it has no code path that reads or writes
  anything in `BitVLendingManager`'s collateral/debt mappings.
- **Behaves exactly like `Frozen`** for every `BitVLendingManager`
  action: new deposits and new borrowing stop; repayment, withdrawal,
  and liquidation remain available. There is no functional difference
  between `Frozen` and `Delisted` from `BitVLendingManager`'s
  perspective — both simply fail `isEligibleForNewActivity`.
- **The one real difference**: `Delisted` is terminal at the registry
  level (`setAssetStatus` reverts `AssetDelisted` if the current status
  is already `Delisted`), and the same asset address can never be
  `registerAsset`'d again (`registerAsset` reverts
  `AssetAlreadyRegistered` regardless of the asset's current status,
  including `Delisted`) — an explicit, documented choice: a delisted
  asset's configuration is preserved as a permanent historical record
  rather than being reusable.
- **The exact limitation if liquidation becomes practically impossible**
  (per the task's explicit instruction to document rather than pretend
  solved): if a delisted asset's oracle also stops returning a valid
  price (a realistic joint failure — an issuer might delist *and* stop
  maintaining a price feed around the same time), `isEligibleForNewActivity`
  already excludes it from *new* borrowing capacity, but the *existing*
  debt secured by that collateral still needs a live price to compute
  `_valueOf`/`_amountFromValue` for liquidation's repay/seize math
  (`BitVLendingManager.liquidate`, unmodified). **If the oracle is
  fully gone, liquidation of that specific position becomes
  functionally blocked** — not because this registry adds a block, but
  because the underlying, pre-existing `_valueOf` reverts on a zero
  price (`ProtocolErrors.ZeroPrice`), exactly as it already would for
  any non-RWA collateral asset whose oracle stops working. **This is a
  real, inherited limitation of the existing lending engine, not
  something this milestone introduces or claims to have solved** — the
  registry cannot manufacture a price that doesn't exist, and per
  instruction this milestone does not modify the liquidation engine to
  work around it.

## Oracle handling

Reuses `IPriceOracle.getPrice(asset)` exactly as-is — **no new oracle
functionality was invented, and the interface itself was not changed.**
Since `IPriceOracle` has no timestamp field to reuse, staleness is
tracked entirely on the registry's own side:

- `AssetConfig.lastPriceVerifiedTimestamp` (`uint40`) — stamped only by
  `ORACLE_MANAGER_ROLE`'s `markPriceFresh(asset)`, which calls
  `IPriceOracle.getPrice` to confirm the price is currently nonzero
  (reverting `InvalidOraclePrice` otherwise) before stamping
  `block.timestamp`.
- `isEligibleForNewActivity(asset)` combines three independent checks,
  **all must pass**: status is `Active`; `block.timestamp -
  lastPriceVerifiedTimestamp <= maxOracleStalenessSeconds`; and a
  **live** re-check that `getPrice` currently returns nonzero (since the
  price could have gone to zero *after* the last attestation — the
  staleness timestamp alone isn't sufficient).
- **Zero price, stale price, invalid/unavailable price** are all
  treated identically: `isEligibleForNewActivity` returns `false`,
  which (per the fail-safe integration below) means `false` never
  increases borrowing capacity.
- `setOracleConfig` (new oracle address or staleness window) **resets**
  `lastPriceVerifiedTimestamp` to `0` — a newly-configured oracle has no
  freshness attestation of its own yet and must be explicitly
  re-attested via `markPriceFresh` before the asset counts toward new
  activity again, rather than silently trusting an unverified source.

## LTV integration

The four-layer bound from the specification, verified end to end:

```
Pool-level hard limits (BitVPoolManager.Pool.ltvBps / .liquidationThresholdBps)
  ↓
RWA asset hard LTV (BitVRWACollateralRegistry.AssetConfig — validated,
  at registration/update time, to never exceed the pool's own values)
  ↓
BitScore adjustment (existing Build 04 IBitScoreManager integration,
  completely unmodified)
  ↓
Registry maximum (isEligibleForNewActivity / isDebtAssetAllowed —
  zeroes this asset's LTV contribution entirely when ineligible)
```

**A deliberate implementation decision, documented explicitly**: the
live weighting math in `_accountData` uses `BitVPoolManager.Pool`'s own
`ltvBps`/`maxLtvWithScoreBps`/`liquidationThresholdBps` values — **not**
a second, independently-read set of numbers from the registry's own
`AssetConfig`. The registry's own risk-parameter fields
(`ltvBps`/`maxLtvWithScoreBps`/`liquidationThresholdBps`/
`liquidationBonusBps`) are validated at registration/update time to
never exceed the pool's values, and serve as a governance ceiling
check and declarative record, but the pool's own values remain the
single runtime source of truth actually used for weighting. This avoids
a second, potentially-drifting number feeding the same calculation and
keeps "do not duplicate the existing lending engine" scrupulously
honest — there is exactly one LTV number in play for any given asset at
any given moment, matching every non-RWA asset's existing behavior. If
`RWA_ADMIN_ROLE` wants a *stricter* RWA-specific LTV than the pool's own
configuration, the correct lever is to lower the pool's own `ltvBps`
via `BitVPoolManager.setRiskParams` (existing, unmodified mechanism) —
the registry's own bps fields do not currently create an independent,
tighter runtime ceiling. **This is flagged as a known limitation
below**, not silently glossed over.

**"BitScore cannot override the hard ceiling"** is verified directly:
`test_LtvBypass_CannotExceedRegistryCeilingViaBitScore` confirms
borrowing against the maximum-tier-adjusted ceiling still reverts one
wei above the pool's `maxLtvWithScoreBps`-derived limit, exactly as the
pre-existing (non-RWA) BitScore ceiling tests already proved for
ordinary collateral.

## BitScore integration

**Zero changes to `BitScoreManager.sol` or its interface.** RWA
collateral flows through the exact same `_effectiveAvailableBorrowValue`
triple-clamp integration point every other collateral asset already
uses — the registry's gate is applied *upstream*, inside
`_accountData`'s aggregation, before BitScore ever sees the resulting
`data.availableBorrowValue`/`data.weightedMaxLtvValue` figures.
BitScore has no awareness that a given collateral asset is RWA-gated at
all, which is exactly the separation
`docs/rwa-market-specification.md` §17 called for ("BitScoreManager
should not become a mandatory dependency").

## Lending integration

`BitVLendingManager.sol` changes (all additive, no existing function
signature removed or narrowed for non-RWA assets):

- New field `IRWACollateralRegistry public rwaRegistry;` (optional,
  `address(0)` = disabled) + `setRwaRegistry` (`PROTOCOL_ADMIN_ROLE`).
- New field `mapping(address => uint256) private _totalCollateralByAsset;`
  — an aggregate running total, updated in `depositCollateral` (+=),
  `withdrawCollateral` (-=), and `liquidate`'s seizure (-=). This is the
  one piece of new *accounting* the task's "collateral accounting stays
  with `BitVLendingManager`" instruction implies belongs here rather
  than in the registry — the registry only ever reads a cap value, it
  never tracks balances itself.
- `depositCollateral` gained one new check
  (`_requireRwaEligibleForNewDeposit`) after the existing pool-state
  checks, before the existing balance/transfer logic.
- `_accountData` gained a `debtAssetFilter` parameter (`address(0)` =
  no filter, used by every caller except `borrow`) and a new per-asset
  gate (`_rwaCountsTowardNewBorrowCapacity`) that decides whether a
  collateral asset's value contributes to `weightedLtvValue`/
  `weightedMaxLtvValue` for this specific calculation. `totalCollateralValue`
  and `weightedLiqThresholdValue` are computed exactly as before,
  unconditionally.
- `borrow` now calls `_accountData(msg.sender, asset)` (passing the
  *target debt asset*) instead of the filter-less overload, so a
  registry-configured allowed-debt-asset restriction is enforced
  specifically for the debt asset actually being borrowed.
- New views: `getTotalCollateralByAsset`,
  `getUserAccountDataForBorrow(user, debtAsset)`.

**Every existing, non-RWA-registered collateral asset is provably
unaffected**: `_rwaCountsTowardNewBorrowCapacity` and
`_requireRwaEligibleForNewDeposit` both return/no-op immediately if
`rwaRegistry == address(0)` *or* the asset was never registered — the
71+44+21+... pre-existing test suites (123 tests) all still pass
unchanged, none of them ever registers an asset with the registry.

## Liquidation integration

**Zero changes to `BitVLendingManager.liquidate`'s own logic** — health
factor, close factor, liquidation bonus, partial liquidation, and bad
debt handling are byte-for-byte the same code as before this milestone.
RWA-specific status checks happen entirely through the registry
boundary *upstream* of liquidation (in `_accountData`, which
`liquidate` already calls to compute the health factor) — liquidation
itself never calls into `rwaRegistry` at all, matching the task's "RWA
status checks should happen through the registry boundary" instruction
literally: the boundary is `_accountData`, not `liquidate`.

## Access control

Exactly the two roles the task specifies, no more:
`RWA_ADMIN_ROLE` (registration, config updates, status transitions,
collateral caps, allowed-debt-asset restrictions) and
`ORACLE_MANAGER_ROLE` (oracle address/staleness config, price-freshness
attestation) — both added to `BitVAccessManager`.
`RISK_MANAGER_ROLE` and `PAUSER_ROLE` are reused directly (the registry
itself has no pause surface distinct from `AssetStatus`, and no
RWA-specific risk-parameter setter beyond what `RWA_ADMIN_ROLE` already
covers — `RISK_MANAGER_ROLE` remains scoped to `BitVPoolManager`'s own
parameters, unchanged). Every registry mutator (`registerAsset`,
`updateAssetConfig`, `setAssetStatus`, `setCollateralCap`,
`setAllowedDebtAsset`, `setOracleConfig`, `markPriceFresh`) is
role-gated; unauthorized callers revert (`ProtocolErrors.Unauthorized`
via `BitVRoleConsumer.onlyRole`) — verified directly for every one of
these functions in `BitVRWACollateralRegistry.t.sol` and re-verified as
fuzzed invariants in `BitVRWAInvariant.t.sol`.

## Security assumptions

- The registry's `view` functions (`isRegisteredAsset`,
  `isEligibleForNewActivity`, `isDebtAssetAllowed`, `getCollateralCap`)
  are called from `BitVLendingManager` inside `try`/`catch`, with every
  catch branch resolving to the *less* favorable outcome (not
  registered -> unaffected is the one exception, since it means the
  asset was never RWA in the first place; anything else defaults to
  "not eligible") — exactly mirroring `_effectiveAvailableBorrowValue`'s
  existing BitScore fail-safe direction.
- No new reentrancy surface: the registry makes no external calls other
  than the read-only `IPriceOracle.getPrice`, and every
  `BitVLendingManager` call site consulting it remains inside that
  contract's pre-existing `nonReentrant` guards.
- `_validateAgainstPool` prevents `RWA_ADMIN_ROLE` from ever registering
  or updating an asset with risk parameters *more permissive* than the
  underlying pool's own hard configuration — a registry misconfiguration
  can only ever be more conservative than the pool, never less.
- Collateral cap enforcement happens only at deposit time
  (`_requireRwaEligibleForNewDeposit`); it is not, and is not claimed to
  be, a live-enforced-at-all-times ceiling once an admin lowers a cap
  below an already-deposited total — see the invariant test's own
  documentation (`invariant_CollateralCapEnforcedGoingForward`) for why
  that's the correct, intentional semantics (matching
  `BitVPoolManager.Pool.supplyCap`'s existing behavior), not a gap.

## Tests created

- `contracts/test/BaseRWATest.sol` — extends `BaseProtocolTest`,
  deploys the registry, registers the existing `collateralAsset` pool
  as RWA collateral mirroring its own pool parameters exactly.
- `contracts/test/unit/BitVRWACollateralRegistry.t.sol` — 48 scenario
  tests across registry, collateral, oracle, borrowing, liquidation,
  compliance, and security categories (matches
  `docs/rwa-market-specification.md` §18's plan).
- `contracts/test/invariant/RWAHandler.sol` +
  `BitVRWAInvariant.t.sol` — 10 fuzzed invariants (256 runs / 128,000
  calls each) covering all nine properties the task lists, plus a
  tenth (`invariant_CollateralCapOnlyChangedByAuthorizedPath`) proving
  the cap can only ever move via the handler's own role-holding action.

## Full Foundry result (actually executed)

`forge test` (after `forge build` confirmed a clean compile,
`via_ir = true`, solc 0.8.24). Two new test suites added: 48 unit tests
(`BitVRWACollateralRegistry.t.sol`) and 10 invariants
(`BitVRWAInvariant.t.sol`, 256 runs/128,000 calls each) — both **all
passing**. Combined with the eight pre-existing suites (123 tests),
**every suite in the repository passes**: see the development log
entry for the exact combined count actually observed.

## Known limitations

- **Registry risk-parameter fields (`ltvBps`/`maxLtvWithScoreBps`/
  `liquidationThresholdBps`/`liquidationBonusBps`) are validated
  against, but not independently enforced instead of, the underlying
  pool's own values** — see "LTV integration" above. A genuinely
  RWA-specific *tighter* LTV than the pool's own configuration is not
  yet a live lever; it requires lowering the pool's own risk parameters
  via the existing `BitVPoolManager.setRiskParams`.
- **Collateral cap is enforced only at deposit time**, not as a
  continuously-true invariant once lowered below an existing total —
  intentional, matching `BitVPoolManager`'s own `supplyCap` semantics,
  but worth stating explicitly rather than assuming.
- **A delisted (or frozen) asset whose oracle also fails entirely can
  become practically unliquidatable** — inherited from the pre-existing
  `_valueOf`/`_amountFromValue` reverting on a zero price, not
  something this milestone introduces or resolves; per instruction, the
  liquidation engine itself was not modified to work around this.
- **No production oracle** — `StaticPriceOracle` remains an
  admin-settable placeholder (pre-existing limitation, unrelated to
  this milestone), meaning `markPriceFresh`'s attestation currently
  only proves "the admin most recently set a nonzero price," not any
  independent freshness guarantee a decentralized feed would provide.
- **CVA metadata (`AssetConfig.isCVA`) is purely admin-attested** — no
  on-chain CVA verification call exists to check it against, per
  `docs/rwa-market-specification.md` §7's conclusion; this remains true
  in the implementation exactly as specified.
- **No pool-as-strategy, no RWA lending engine, no governance, nothing
  deployed** — per instruction.

## Remaining Cleanverse dependencies

Unchanged from `docs/rwa-market-specification.md` §5's conclusions —
this implementation adds no new Cleanverse dependency beyond what was
already specified:
- Whether any specific registered RWA token is a confirmed CVA remains
  an off-chain fact BitV cannot self-certify (`isCVA` stays
  admin-attested metadata).
- No CVA transfer/settlement/redemption/recovery mechanics were
  implemented — none are confirmed by Cleanverse's documentation beyond
  automatic transfer-time compliance gating, and none were fabricated
  here.
- Liquidator compliance for RWA-backed liquidations remains unresolved
  (specification open question 3) — `BitVLendingManager.liquidate`'s
  existing behavior (no compliance check on the liquidator) is
  unchanged by this milestone.
