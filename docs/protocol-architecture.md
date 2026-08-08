# BitV Protocol Architecture — Core Pool & Lending (Build 03)

**Scope:** permissioned liquidity pools, lending, borrowing, repayment,
collateral management, liquidation. Explicitly out of scope: BitScore,
yield vaults, RWA markets, governance, cross-chain, deployment.

This is BitV's own economic design — none of it is a Cleanverse claim.
Where Cleanverse is involved (the compliance gate), see
`docs/cleanverse-integration.md` for what's confirmed vs. `UNCONFIRMED`.

## Pool architecture

`BitVPoolManager` is one contract, one pool per underlying asset
(`DataTypes.Pool`, keyed by asset address). Each pool tracks:

- `totalScaledSupply` / `totalScaledDebt` — ray-scaled (1e27) balances,
  the same pattern Aave uses: a user's real balance is
  `scaledBalance * currentIndex`, so interest accrual is a single index
  update rather than iterating every user.
- `liquidityIndexRay` / `borrowIndexRay` — start at `1 ray` (1e27),
  grow monotonically via `accrueInterest`.
- `supplyCap` / `borrowCap` — underlying-unit caps, `0` = uncapped.
- `isPaused` — per-pool emergency pause (`PAUSER_ROLE`).
- `isBorrowingEnabled` / `isCollateralEnabled` — an asset can be a
  supply-only market, a collateral-only asset, both, or (misconfigured)
  neither; `BitVLendingManager` checks these flags before allowing
  borrow/collateral actions against a pool.

Supply-side functions (`deposit`, `withdraw`) are on `BitVPoolManager`
directly and are real on-chain ERC20 transfers + mapping updates — no
off-chain or synthetic balances anywhere. `withdraw(asset,
type(uint256).max)` withdraws the caller's *exact* scaled balance
(converted once, not round-tripped through an underlying-amount
conversion) so `totalScaledSupply` never accumulates rounding dust on a
full withdrawal.

Borrow-side liquidity movement (`borrowFromPool` / `repayToPool`) is
restricted to a single registered `lendingManager` address
(`onlyLendingManager`), set once by `PROTOCOL_ADMIN_ROLE` via
`setLendingManager`. `BitVPoolManager` doesn't know about collateral,
health factors, or specific borrowers — it only tracks aggregate pool
debt for utilization/interest purposes. All per-user debt/collateral
accounting lives in `BitVLendingManager`.

## Lending architecture

`BitVLendingManager` is a **cross-margin** design (like Aave v2/v3, not
isolated pairs): a user can deposit collateral in multiple assets and
borrow multiple assets against their combined collateral value. Per user:

- `_collateralBalance[user][asset]` — raw amount, not scaled (collateral
  doesn't earn yield in this design; only pool suppliers do).
- `_scaledDebt[user][asset]` — ray-scaled, using the *same*
  `borrowIndexRay` as `BitVPoolManager`'s aggregate tracking, read via
  `BitVPoolManager.getBorrowIndex(asset)`.
- `_userCollateralAssets[user]` / `_userDebtAssets[user]` —
  `EnumerableSet.AddressSet`, so cross-asset health-factor calculations
  only iterate assets the user actually holds a position in.

## Collateral model

Any pool with `isCollateralEnabled = true` can back a loan. A user's
borrow capacity and liquidation threshold are computed by summing,
across every collateral asset they hold, that asset's value (via its
configured `IPriceOracle`) weighted by its own `ltvBps` /
`liquidationThresholdBps` — see `BitVLendingManager._accountData`. Assets
without a configured price oracle are skipped from the sum (documented
limitation, not a silent revert) rather than blocking the whole
calculation.

## Interest model

`KinkedInterestRateModel` (per `IInterestRateModel`) — a standard
two-slope curve:

```
utilization <= kink:  rate = base + (utilization / kink) * slope1
utilization >  kink:  rate = base + slope1
                            + ((utilization - kink) / (1 - kink)) * slope2
```

`base` is the flat component; the rest is the utilization component —
kept as separate, named parameters rather than one opaque formula, per
the "separate base and utilization" requirement. Suggested (not
deployed) starting parameters are documented directly in
`KinkedInterestRateModel.sol`'s trailing comment, not left unexplained.

**Accrual is simple (linear) interest over the elapsed period**, applied
once per `accrueInterest(asset)` call:
`borrowIndexRay += borrowIndexRay * (borrowRateRay * elapsedSeconds / 365 days)`.
This is a deterministic, auditable approximation — not continuous
compounding — chosen so the exact index value after N seconds is easy to
hand-verify, at the cost of slightly under-accruing versus a
continuously-compounded model over the same period. `accrueInterest` is
called at the start of every state-changing pool/lending action that
depends on current balances, plus explicitly before any health-factor
computation in `BitVLendingManager` (`_accrueAllUserAssets`, which
accrues every asset in the user's debt set, not just the one being acted
on).

A `reserveFactorBps` share of each pool's accrued interest is minted as
additional scaled supply credited to `BitVTreasury`'s address — it
compounds like any other supplier's deposit rather than needing separate
treasury-accrual bookkeeping.

## Liquidation model

A position is liquidatable when its health factor
(`liquidationThreshold-weighted collateral value / total debt value`,
ray-scaled) drops below `1 ray`. `BitVLendingManager.liquidate(user,
debtAsset, collateralAsset, repayAmount)`:

1. Reverts `PositionIsHealthy` if health factor `>= 1 ray`.
2. Caps the repay at `currentDebt.percentMul(closeFactorBps)` —
   default 50% (`closeFactorBps`, `RISK_MANAGER_ROLE`-settable) — a
   documented, industry-common (Aave-style) default, not derived from
   any BitV-specific requirement. This is what makes **partial
   liquidation** possible: a liquidator can't be forced to (or allowed
   to) close more than half a position in one call.
3. Computes `seizeValue = repayValue * (1 + liquidationBonusBps)` and
   converts to the collateral asset via its oracle price —
   **liquidation bonus**.
4. **Insolvency handling**: if the computed seize amount exceeds the
   user's actual collateral balance, seizure is capped at what's there
   and the repay amount is scaled down proportionally, so a liquidator
   never pays more than the collateral they receive is worth. This can
   leave residual, unrepaid "bad debt" on the position — a known,
   documented tradeoff (see Security Assumptions below), not silently
   hidden or reverted into a stuck state.
5. **Repeated liquidation**: each call recomputes health factor and
   current debt fresh from state, so a second `liquidate` call on the
   same still-unhealthy position after a first partial one operates
   correctly on the reduced debt — there's no cached/stale state that
   could double-count.
6. Effects (collateral debit, debt reduction) happen before external
   token transfers (checks-effects-interactions), and the whole function
   is `nonReentrant`.

## Treasury flow

`BitVTreasury.receiveFee(asset, amount)` pulls funds from any caller
(currently only the reserve-factor-share minting mechanism inside
`BitVPoolManager.accrueInterest`, which credits scaled supply directly
rather than calling `receiveFee` — see Interest model above). Treasury
withdrawal (`withdraw`) is `PROTOCOL_ADMIN_ROLE`-gated. No governance
(multisig/DAO voting) yet — a single role, not a voting mechanism, per
this milestone's explicit scope.

## Compliance flow

Every protected action across `BitVPoolManager` and
`BitVLendingManager` calls `_requireCompliance(msg.sender)`
(`BitVComplianceGuard`, unchanged from Build 02.x) as the **first**
operation, before any state read or mutation:
`deposit`, `withdraw`, `depositCollateral`, `withdrawCollateral`,
`borrow`, `repay`, `liquidate` (the liquidator, not the liquidated user,
is compliance-checked — they're the one taking custody of seized
collateral).

The Cleanverse validator address remains constructor-supplied,
`immutable`, and never hardcoded — see `contracts/script/Deploy.s.sol`,
which reads `CLEANVERSE_VALIDATOR_ADDRESS` from the environment and
reverts if unset, rather than defaulting to anything. This script is a
template only — **not executed**, since Cleanverse's Monad Testnet
deployment remains `UNCONFIRMED` (see
`docs/cleanverse-integration.md`).

## Administrative roles

`BitVAccessManager` (OpenZeppelin `AccessControl`), four roles, checked
via `BitVRoleConsumer.onlyRole` in `BitVPoolManager` /
`BitVLendingManager` / `BitVTreasury`:

| Role | Grants |
|---|---|
| `PROTOCOL_ADMIN_ROLE` | Pool creation, setting `lendingManager` on `BitVPoolManager`, treasury withdrawal |
| `RISK_MANAGER_ROLE` | Risk params (LTV/liquidation threshold/bonus), caps, reserve factor, interest rate model/oracle assignment, close factor |
| `POOL_MANAGER_ROLE` | Enabling/disabling borrowing or collateral use on an existing pool |
| `PAUSER_ROLE` | Emergency pause only — deliberately narrower than `PROTOCOL_ADMIN_ROLE` |

Users are never granted any of these roles. This is separate from
`BitVComplianceGuard`'s `Ownable` (each protected contract also has an
`owner`, used *only* for Cleanverse's documented `RuleV2`
rule-management pattern — see `docs/cleanverse-integration.md` §"Single-
Contract Mode" — not for protocol economics).

## Security assumptions

- **Reentrancy**: every state-changing external function on
  `BitVPoolManager` and `BitVLendingManager` is `nonReentrant`
  (OpenZeppelin `ReentrancyGuard`), *in addition to* checks-effects-
  interactions ordering (state updated before external calls) —
  defense in depth, not either/or. Verified with a real malicious-token
  reentrancy attempt (`MockReentrantERC20`), not just asserting the
  modifier exists — see `test_Reentrancy_MaliciousTokenCannotReenterDeposit`.
- **Integer precision / arithmetic**: all interest/health-factor math
  uses `WadRayMath` (1e27) or `PercentageMath` (1e4 bps) with rounding
  built into the library functions (`+halfB` before dividing), not ad
  hoc division. Solidity 0.8.24's built-in overflow/underflow checks are
  relied on rather than `unchecked` blocks anywhere in this milestone's
  code.
- **Unauthorized parameter changes**: every admin function is
  role-gated; unauthorized calls revert `ProtocolErrors.Unauthorized`
  (or OZ's own `AccessControlUnauthorizedAccount` for `BitVTreasury`'s
  underlying `AccessControl` checks), verified in tests.
- **Insolvency**: liquidation caps seizure at actual collateral balance
  rather than reverting/blocking when a position is deeply underwater —
  this can leave bad debt on a position (no debt is force-written off;
  it just becomes unrecoverable by any single liquidator once collateral
  is exhausted). Socializing or otherwise handling accumulated bad debt
  is **not implemented** — out of scope for this milestone, flagged here
  rather than left implicit.
- **Flash-loan manipulation**: BitV has no flash-loan feature in this
  milestone. The main flash-loan-adjacent risk in a lending protocol —
  a manipulated spot price used for collateral valuation within a single
  transaction — is a property of *whatever oracle is configured*, not of
  BitV's contracts. `StaticPriceOracle` (admin-set, explicitly
  non-production, see its NatSpec) can't be flash-loan-manipulated since
  it isn't reading any market at all; a real deployment's oracle choice
  is what determines this protection, which is why `IPriceOracle` is a
  clean interface rather than a specific price source baked in.
- **Donation attacks** (inflating `totalSupplied`/index math by directly
  transferring tokens to the pool contract rather than calling
  `deposit`): `BitVPoolManager`'s supply accounting is index-based
  (`totalScaledSupply` × `liquidityIndexRay`), not derived from
  `IERC20.balanceOf(address(this))` for share pricing — only
  `availableLiquidity` reads the raw balance, and that's used purely as
  a withdrawal/borrow ceiling, not as the basis for computing anyone's
  share value. A direct token donation increases available liquidity
  without minting any scaled supply, which doesn't dilute or inflate any
  user's `balanceOf` — there's no first-depositor/share-price attack
  surface here because there are no transferable pool shares at all
  (unlike an ERC4626-vault donation attack).
- **Incorrect share accounting**: `withdraw(asset, type(uint256).max)`
  is deliberately implemented to derive the scaled amount from the
  user's *exact* stored scaled balance rather than round-tripping
  through an underlying-amount conversion (the same class of bug fixed
  in an earlier BitV milestone's `PoolManager.withdraw`) — see the
  `test_Withdraw_Max_WithdrawsExactBalanceNoDust` test.
- **Liquidation edge cases**: partial liquidation (close factor),
  repeated liquidation on the same position, and insolvent positions are
  all covered by dedicated tests in `BitVLiquidation.t.sol` (not merely
  asserted in prose) — see that file and the Testing section of
  `docs/development-log.md`'s Build 03 entry for exactly which scenarios
  were exercised vs. which remain conceptual.
- **Oracle assumptions**: no oracle dependency was introduced beyond
  what the architecture actually requires (cross-asset collateral
  valuation is unavoidable in a multi-asset lending design). The
  interface (`IPriceOracle`) is clean and swappable;
  `StaticPriceOracle` is explicitly documented as non-production
  (single-admin-controlled price, trivially manipulable by that admin) —
  see its NatSpec. No specific production price source is chosen or
  assumed in this milestone.

## Explicitly not built (per Build 03 scope)

BitScore (risk scoring — `BitScoreManager` remains an unmodified
skeleton), yield vaults (`BitVVaultManager` remains an unmodified
skeleton), RWA markets, governance (multisig/DAO), cross-chain
functionality, and production deployment (no contract has been deployed
anywhere).
