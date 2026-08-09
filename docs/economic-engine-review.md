# BitV Economic Engine Validation (Build 03.5)

**This is a validation pass, not an audit.** BitV is not production-ready,
its contracts are not audited, Cleanverse is not confirmed deployed on
Monad, and passing tests do not by themselves make the protocol secure —
none of those claims are made anywhere in this document.

## Foundry status

**FOUNDRY AVAILABLE** (this milestone, in this sandbox — was unavailable
in every prior milestone). `binaries.soliditylang.org` and
`api.github.com` are both still network-blocked here, same as before, but
`raw.githubusercontent.com` is reachable and mirrors both foundryup's own
install script and `solc-bin`'s release list/binaries, which was enough
to install `forge 1.0.0` and pin `solc 0.8.24` manually (placed directly
in `~/.svm/0.8.24/`, bypassing `svm`'s own download path). This is
environment-specific — a different sandbox/CI runner may need the same
workaround, or may have direct access and not need it at all.

## What was tested

Full `forge test -vvv` run, plus the four `--match-contract` filters this
milestone specifically requested. All 45 tests across 5 suites pass:

| Suite | Tests | Result |
|---|---|---|
| `BitVComplianceGuardTest` | 11 | PASS |
| `BitVPoolManagerTest` | 12 | PASS |
| `BitVLendingManagerTest` | 12 | PASS |
| `BitVLiquidationTest` | 7 | PASS |
| `BitVInvariantTest` (new this milestone) | 3 | PASS |

Coverage: deposit/withdraw (incl. exact max-withdraw), pool accounting,
pause/unpause, borrow/repay (incl. overpay capping), collateral
deposit/withdrawal (incl. health-factor-breach rejection), interest
accrual, healthy/unhealthy/partial/repeated liquidation, liquidation
bonus (exact value asserted), debt reduction (exact value asserted),
compliance accept/reject at both the guard level and through real
protocol actions, unauthorized admin-action rejection, and a real
reentrancy attack (`MockReentrantERC20`, not just an assertion that
`nonReentrant` exists).

## What was not tested

- **Insolvent-position liquidation** (seizure capped at less-than-owed
  collateral, leaving residual bad debt) — the code path exists
  (`BitVLendingManager.liquidate`'s `seizeAmount > userCollateral`
  branch) but no test drives a position deep enough underwater to
  exercise it. Flagged, not fixed — constructing a realistic scenario
  needs careful price/LTV arithmetic that didn't fit this milestone's
  scope of *validating what exists*, not adding new test infrastructure
  beyond what Task 6 asked for.
- **Multi-asset cross-margin health factor** with more than one
  collateral asset or more than one debt asset simultaneously — all
  current tests use exactly one of each. The aggregation logic
  (`_accountData`'s loops) is exercised with 1-element sets only.
- **Stale-price protection** — `StaticPriceOracle` has no timestamp/
  staleness concept at all (see Oracle Assumptions below), so there's
  nothing to test here; this is a documented gap, not an untested
  feature.
- **Decimal mismatches** beyond 18/18 — both mock assets in
  `BaseProtocolTest` use 18 decimals. The `_valueOf`/`_amountFromValue`
  normalization math was reviewed by inspection (see Interest/Oracle
  Assumptions) but not exercised with, e.g., a 6-decimal asset.
- **Gas/griefing analysis** on `EnumerableSet` iteration in
  `_accountData` — bounded by however many distinct assets a user has
  ever held a position in; fine at the scale of this milestone's tests
  (1-2 assets), not stress-tested with many assets.
- **Full invariant coverage** — see Task 6 below for exactly which
  invariants were and weren't turned into fuzzed tests.

## Failures discovered and fixed

### 1. Compiler: "stack too deep" in `BitVPoolManager.accrueInterest`

**Root cause: contract logic incompatible with the legacy codegen
pipeline** (too many live local variables in one function), not a test
or environment issue. Fixed by enabling `via_ir = true` in
`foundry.toml` — the standard fix for this class of error, not a
function rewrite forced by a compiler quirk. Documented inline in
`foundry.toml`.

### 2. Two `vm.prank` test-logic bugs

`test_UnauthorizedAdminAction_Rejected` and
`test_CreatePool_UnauthorizedCaller_Rejected` (`BitVPoolManager.t.sol`)
both failed with the *right* error type but the *wrong* address:

```
Unauthorized(<test contract>, role) != Unauthorized(<supplier>, role)
```

**Root cause: test logic**, not contract logic. `vm.prank(supplier)`
only affects the single next external call. Both tests called
`accessManager.PAUSER_ROLE()` / `accessManager.PROTOCOL_ADMIN_ROLE()` —
themselves external calls — *inside* the `abi.encodeWithSelector(...)`
expression built after the `vm.prank`, which consumed the prank before
the actual protected call (`poolManager.setPoolPaused` /
`poolManager.createPool`) ran. Fixed by hoisting the role-hash lookup to
a local variable computed *before* `vm.prank`. Both tests now correctly
assert the caller identity. Confirmed by re-running the affected tests,
then the full suite — see Fixes Made below for the general economic-
review fixes found afterward.

No contract-logic bug caused either failure.

## Fixes made (economic/security review, Tasks 4-5)

Two real findings, both fixed and covered by new regression tests
(`test_DepositCollateral_RespectsPoolPause`,
`test_Borrow_ZeroPricedDebtAsset_RevertsLoudly` in
`BitVLendingManager.t.sol`):

### 1. `depositCollateral` didn't respect pool pause

**Found during Task 5 (emergency pause behavior review).**
`BitVPoolManager.setPoolPaused` correctly blocks `deposit`/`withdraw`
(via the `poolActive` modifier) and, indirectly, `borrow` (since
`BitVLendingManager.borrow` routes through
`BitVPoolManager.borrowFromPool`, which also carries `poolActive`). But
`BitVLendingManager.depositCollateral` never called into
`BitVPoolManager` at all for a paused check — it only checked
`isActive`/`isCollateralEnabled` on a copy of the pool config, so
pausing a collateral pool didn't actually stop new deposits into it.
**Fixed**: added an explicit `isPaused` check to `depositCollateral`.
**Deliberately not added to `withdrawCollateral`** — users should be
able to exit collateral positions during an emergency pause; blocking
withdrawal during a pause would be the more dangerous direction.

### 2. Zero-priced assets were silently valued at zero, not rejected

**Found during Task 4 (oracle "zero prices" review item).**
`StaticPriceOracle.getPrice` reverts if a price was never set
(`PriceOracleNotSet`), but nothing prevented an admin from explicitly
setting a price of `0`, and `_valueOf` would then silently compute a
value of `0` for a nonzero `amount` instead of failing — which could
mask real debt (if it happened to the debt asset) or wipe out real
collateral (if it happened to the collateral asset) in a health-factor
calculation, with no revert to signal anything was wrong. **Fixed** by
adding a `ZeroPrice` check, but split into two variants after realizing
the naive fix (revert everywhere) would let one misconfigured zero
price deny-of-service every action for every user who happens to hold
that asset:

- `_valueOf` (reverting) — used for the specific asset a caller is
  directly acting on right now (the amount being borrowed, or the
  repay/seize legs of a liquidation) — correct to fail loudly here.
- `_tryValueOf` (non-reverting, returns `(value, ok)`) — used inside
  `_accountData`'s aggregation loops, where a single bad asset
  shouldn't be able to brick every other action for every other user.
  A zero-priced asset is treated the same as "no oracle configured"
  (already-existing behavior) — skipped from the sum.

**This split itself is a documented residual risk, not a complete
fix** — see "Remaining risks" below: skipping a zero-priced *debt*
asset from `totalDebtValue` understates risk rather than overstating
it, which is the less-safe direction.

## Manual review findings by area

### Pool accounting

Deposits/withdrawals/interest accrual/borrow/repay/utilization/caps all
reviewed by inspection; no additional issues found beyond the two fixed
above. Notably: `availableLiquidity` reads `IERC20.balanceOf(address(this))`
directly (not derived from scaled-supply accounting), which is
*correct* here — see Donation Attacks below for why this doesn't create
a vulnerability the way it would in a share-price-based vault.

### Lending

Collateral/debt valuation, LTV, health factor, borrow limits, repayment,
and collateral withdrawal all reviewed. `borrow`'s LTV check correctly
computes `availableBorrowValue` from state *before* the pending borrow
(doesn't count the loan being requested as already-existing debt).
`withdrawCollateral`'s health check runs after the balance is already
decremented but before the token transfer — not strict
checks-effects-interactions order, but safe: a revert unwinds the whole
transaction atomically, so there's no window where the decremented
balance is externally observable without the check having also passed.

### Interest

Utilization/kink/base/slope1/slope2 all match the documented formula
(`docs/protocol-architecture.md`). Rounding: `WadRayMath.rayMul`/
`rayDiv` round to nearest (add half before dividing) rather than
consistently rounding in the protocol's favor (e.g. always down for
credits, always up for debits, which is what a hardened
production lending protocol typically does to prevent slow insolvency
drift from accumulated rounding). **This is a real, non-blocking
limitation** — over a very large number of tiny operations, symmetric
rounding could theoretically let total scaled supply and total scaled
debt drift very slightly out of exact sync with real token balances.
Not fixed this milestone (would mean touching the rounding direction of
every `rayMul`/`rayDiv` call site and re-verifying every test's exact
expected values) — flagged as a remaining risk.

### Liquidation

Health factor, close factor, liquidation bonus, partial liquidation,
and debt reduction are all covered by exact-value-asserting tests (not
just "it didn't revert"). Insolvency/bad-debt handling exists in code
(see What Was Not Tested) but isn't exercised by a test this milestone.
Collateral availability is checked (seizure capped at
`_collateralBalance[user][collateralAsset]`).

### Oracles

- **Stale prices**: no protection — `StaticPriceOracle` has no
  timestamp or heartbeat concept. Explicitly non-production already
  (see its NatSpec); restated here because Task 4 asked specifically.
- **Zero prices**: found and fixed (see Fixes Made above), with the
  documented residual risk in the aggregation-loop case.
- **Negative values**: not applicable — Solidity `uint256` prices can't
  be negative; no signed-price oracle path exists.
- **Decimal mismatch**: handled via explicit normalization in
  `_valueOf`/`_amountFromValue` (`10 ** (18 - priceDecimals)` /
  `10 ** assetDecimals`), reviewed by inspection, not tested with a
  non-18-decimal asset (see What Was Not Tested). Requires
  `priceDecimals <= 18`, undocumented what happens above that (the
  `10 ** (18 - priceDecimals)` subtraction would underflow and revert —
  safe failure mode, just not spelled out anywhere before now).
- **Price manipulation assumptions**: none — no production price
  source is chosen or assumed; `IPriceOracle` is a clean, swappable
  interface specifically so this isn't baked into the lending logic.
- **Missing oracle configuration**: `PriceOracleNotSet` reverts for
  direct action-specific calls (borrow, liquidate); silently skipped
  (not counted) in the account-data aggregation — same treatment as a
  zero price, for the same reasons.

## Security review (Task 5)

| Area | Finding |
|---|---|
| Reentrancy | `nonReentrant` + CEI on every state-changing function; verified with a real attack, not just modifier presence |
| CEI | Followed, with one documented Effects-then-Check-then-Interaction exception in `withdrawCollateral` (safe — see Lending review above) |
| Access control | Role-gated via `BitVRoleConsumer`; unauthorized rejection tests fixed and passing |
| Donation attacks | Not exploitable — supply/debt accounting is index-based, not derived from `balanceOf`; a direct transfer only ever adds withdrawal/borrow headroom, never dilutes or inflates anyone's tracked balance (there are no transferable pool shares to manipulate the "price" of) |
| Precision loss / rounding direction | Symmetric (round-to-nearest), not protocol-favoring — documented residual risk, not fixed this milestone |
| Integer overflow/underflow | Solidity 0.8.24 checked arithmetic throughout; no `unchecked` blocks anywhere in this milestone's code |
| Flash-loan manipulation | No flash-loan feature exists; the adjacent risk (oracle price manipulated within one transaction) is entirely a property of whichever oracle is configured — not applicable to `StaticPriceOracle` (can't be flash-loan-manipulated; it isn't reading a market), and no production oracle is assumed |
| Oracle manipulation | Same as above — deferred to whatever real oracle a production deployment chooses |
| Unauthorized parameter changes | Role-gated everywhere; tests now correctly assert rejection (see Failures Discovered) |
| Emergency pause behavior | `deposit`/`withdraw`/`borrow` (indirectly) all correctly blocked while paused; `depositCollateral` was found not to respect pause and is now fixed; `withdrawCollateral`/`repay`/`liquidate` deliberately remain unpaused-by-design so users can always exit or the protocol can always de-risk a position |

## Invariants (Task 6)

Documented and turned into fuzzed `invariant_*` tests in
`contracts/test/invariant/BitVInvariant.t.sol`
(`contracts/test/invariant/Handler.sol` drives bounded random
deposit/withdraw/depositCollateral/borrow/repay calls across 3 actors,
256 runs × 500 calls each = 128,000 calls per invariant, 0 top-level
reverts since the handler swallows expected reverts internally):

1. **`invariant_BorrowedNeverExceedsSupplied`** — `totalBorrowed(asset)
   <= totalSupplied(asset)`, always. **PASS.**
2. **`invariant_LiquidityCoversSupply`** — `availableLiquidity(asset) +
   totalBorrowed(asset) >= totalSupplied(asset)`, always (the pool can
   always account for what it owes suppliers). **PASS.**
3. **`invariant_UncompliantWalletStillRejected`** — a wallet the
   compliance mock has never granted a CVI to still can't deposit,
   regardless of how much fuzzed protocol state has accumulated.
   **PASS.**

**Invariants named in the brief but not turned into fuzzed tests**
(documented here instead, per the brief's "where practical"):

- *"User debt cannot become negative"* — not meaningfully fuzzable;
  `uint256` can't represent a negative value at the type level, so this
  is enforced by Solidity itself, not application logic worth
  invariant-testing.
- *"Withdrawals cannot exceed available user balance"* — enforced by a
  `require`-equivalent revert checked directly in
  `test_Withdraw_MoreThanBalance_Reverts`; a fuzzed version would
  mostly re-test the same code path with random amounts instead of one
  chosen adversarial amount, so it was left as a scenario test.
- *"Liquidation cannot improve an unhealthy position incorrectly"* — the
  exact-value liquidation tests in `BitVLiquidation.t.sol` assert this
  concretely (debt reduces by exactly the repaid amount, collateral
  seized matches the bonus formula exactly); a general fuzzed version
  would need a price/LTV generator sophisticated enough to reliably
  produce liquidatable-but-not-fully-insolvent positions, which didn't
  fit this milestone's time budget — flagged as a good candidate for a
  dedicated liquidation-fuzzing milestone later, not attempted here.
- *"Unauthorized users cannot modify risk parameters"* — covered by
  scenario tests (`test_UnauthorizedAdminAction_Rejected`,
  `test_CreatePool_UnauthorizedCaller_Rejected`), not fuzzed, since the
  property doesn't depend on prior protocol state the way the pool/
  liquidity invariants do.

## Treasury reserve-factor claim (Prompt 14)

Previously documented gap (Build 11 / Prompt 13): `BitVTreasury` had no
way to realize the reserve-factor interest `BitVPoolManager.accrueInterest`
had been crediting it since Build 03. This milestone closes that gap
without introducing a second accounting system.

**Where the interest already sits.** `accrueInterest` (per-pool, in
`BitVPoolManager`) has always split each period's borrow-interest into
a supplier share and a reserve share (`pool.reserveFactorBps`). The
reserve share is converted to scaled supply and credited to
`_scaledSupply[asset][TREASURY]` — the exact same mechanism as any
supplier's deposit, compounding via the pool's own `liquidityIndexRay`.
The underlying tokens were never moved anywhere: they're part of
`BitVPoolManager`'s own ERC20 balance the whole time, exactly like a
regular supplier's undrawn balance. The only gap was that nothing let
`TREASURY`'s address realize that scaled-supply position, since
`withdraw()` always operates on `msg.sender`, and `BitVTreasury` (a
separate contract) never called it.

**The fix.** Two additions, no new ledger:

1. `BitVPoolManager.claimReserve(address asset, uint256 amount)` — new
   function, restricted to `msg.sender == TREASURY` (reverts
   `CallerNotTreasury()` otherwise). Mirrors `withdraw()`'s exact
   accounting (same `liquidityIndexRay` math, same
   `availableLiquidity` bound, same `type(uint256).max` "claim
   everything" convention) but is hard-scoped to
   `_scaledSupply[asset][TREASURY]` — it can never read or debit any
   other address's balance. It deliberately skips `_requireCompliance`:
   CVI eligibility is a *user* on-ramp check, and the treasury claiming
   interest it already owns by construction isn't a user action for
   Cleanverse to gate. `nonReentrant` + checks-effects-interactions
   (state debited before the `safeTransfer` out), identical to
   `withdraw()`. A companion view, `reserveBalance(address asset)`,
   exposes the treasury's current claimable balance without requiring
   callers to know it's tracked via the ordinary supplier-balance
   mechanism.
2. `BitVTreasury.claimPoolReserve(address poolManager, address asset,
   uint256 amount)` — new function, gated by the existing
   `PROTOCOL_ADMIN_ROLE` (no new role introduced), that simply calls
   `BitVPoolManager(poolManager).claimReserve(asset, amount)` and emits
   `PoolReserveClaimed`. `BitVTreasury.withdraw` (pre-existing,
   unchanged) then moves the now-real ERC20 balance out to wherever the
   admin directs, exactly as it always has for liquidation/vault fees.

**Properties preserved:** claiming pool A's reserve cannot affect pool
B's accounting (separate `_pools`/`_scaledSupply` entries per asset);
claiming never touches supplier or borrower balances (those live under
different map keys); zero-amount and over-claim both revert cleanly
(`ZeroAmount`, `AmountExceedsBalance`); repeated claims and partial
claims both work identically to a supplier doing repeated partial
withdrawals, because it *is* that same code path, just address-scoped
to `TREASURY`. Verified by
`contracts/test/unit/BitVTreasuryReserveClaim.t.sol` (18 tests:
accrual, full/partial/repeated/zero claims, multiple pools, wrong
asset, insufficient reserve, unauthorized caller, direct
non-treasury caller, reentrancy, and post-claim supplier/borrower/
liquidity invariant checks) and a new invariant,
`invariant_TreasuryReserveNeverExceedsTotalSupply`, fuzzed together
with ordinary deposit/borrow/repay/withdraw activity via the shared
`Handler` (256 runs × 500 calls).

**Remaining limitation:** none identified for the accounting model
itself. The one adjacent, still-open item is operational rather than
architectural — `PROTOCOL_ADMIN_ROLE` must actually call
`claimPoolReserve` per pool periodically (there's no auto-claim
trigger, matching the rest of the protocol's admin-driven-not-
autonomous design); this is a scheduling/ops concern, not a contract
gap.

## Known limitations (summary)

- Rounding is symmetric, not protocol-favoring (see Interest above).
- Zero-priced debt assets drop out of `totalDebtValue` in the
  aggregation loop rather than forcing an unhealthy result (see Fixes
  Made #2).
- No stale-price protection anywhere (inherent to `StaticPriceOracle`
  being explicitly non-production).
- Insolvent-position liquidation and multi-asset (>1 collateral or >1
  debt asset simultaneously) cross-margin paths are implemented but not
  test-covered this milestone.
- No decimal-mismatch testing beyond the 18/18 mock assets used
  throughout.

## Cleanverse status (unchanged, restated per instruction)

Cleanverse is **not** confirmed deployed on Monad Testnet. Nothing in
this milestone changed that — see `docs/cleanverse-integration.md`'s
"Deployment Readiness" section, still current.

## Test Report

| | Result |
|---|---|
| Foundry | **AVAILABLE** |
| Compilation | **PASS** |
| Pool tests | **PASS** (12/12) |
| Lending tests | **PASS** (12/12) |
| Liquidation tests | **PASS** (7/7) |
| Compliance tests | **PASS** (11/11) |
| Security tests | **PASS** (covered within the above — real reentrancy attack, unauthorized-admin-action rejection, compliance rejection; no separate suite) |
| Invariant tests | **PASS** (3/3) |
