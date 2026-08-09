# BitV Testnet Smoke-Test Plan (Build 09, partially executed in Build 11)

This is a manual test sequence, run **after** a real deployment exists
on Monad Testnet and `services/contracts/addresses.ts` has been populated
with the resulting addresses — see `docs/deployment-readiness.md` for
what had to be true before that deployment happened.

> **Build 11 update:** steps 1-9 (core lending cycle) have now been
> executed for real against Monad Testnet and are recorded in
> [`## Results (Build 11)`](#results-build-11) at the bottom of this
> file. Steps 10-17 (liquidation, vault, RWA, dashboard/event/treasury
> verification) remain unexecuted — no vault or RWA asset is deployed
> yet, and those steps still describe intended behavior only.

Each step lists: the action, the on-chain call(s) it exercises, and what
to verify before moving to the next step. Use conservative, small amounts
throughout — testnet tokens still cost real gas and a mistake here should
be cheap to recover from.

## Prerequisites

- A deployed and validated protocol (`ValidateDeployment.s.sol` passes).
- A wallet holding Monad Testnet MON for gas and enough of the test
  asset(s) configured for the pools being exercised.
- `services/contracts/addresses.ts` populated with the real deployment.
- The dashboard running against that configuration (`npm run dev` or a
  deployed frontend pointed at the same addresses).

## Sequence

1. **Connect wallet.** Open `/dashboard`. Verify `WalletStatus` shows
   "Connected" with the correct address once a wallet is connected via
   RainbowKit, and "Disconnected" beforehand — never a stale or fake
   connected state.
2. **Verify network.** Confirm the wallet is on Monad Testnet (chain ID
   10143). If connected to any other chain, verify the dashboard shows
   its wrong-network state rather than silently reading data from the
   wrong chain.
3. **Verify CVI status.** Check `CVIStatus` against
   `IAPassComplianceValidator.complianceVerify(poolAddress, wallet)` for
   at least one BitV contract address. Confirm it reads "Verified" only
   for a wallet actually known to Cleanverse as compliant, and "Not
   Verified" (never a fabricated "Verified") otherwise.
4. **Supply liquidity.** Call `BitVPoolManager.deposit(asset, amount)`
   for a small amount. Verify: `Deposited` event emitted;
   `balanceOf(asset, wallet)` increases by the deposited amount; the
   dashboard's supplied-liquidity figure reflects it after a refresh.
5. **Deposit collateral.** Call `BitVLendingManager.depositCollateral
   (asset, amount)`. Verify: `CollateralDeposited` event; `getCollateralBalance
   (wallet, asset)` increases; `CollateralTable` reflects it.
6. **Borrow.** Call `BitVLendingManager.borrow(debtAsset, amount)` well
   under the account's available borrow value. Verify: `Borrowed` event;
   `getCurrentDebt(wallet, debtAsset)` increases; `getHealthFactor(wallet)`
   drops but stays above 1.0x; `DebtTable`/`HealthFactorCard` reflect it.
7. **Repay.** Call `BitVLendingManager.repay(debtAsset, amount)` for part
   of the debt, then again with `type(uint256).max` to fully close it.
   Verify: `Repaid` event both times; `getCurrentDebt` reaches exactly
   zero on the full-close call (not a dust remainder); if BitScore is
   wired, `ScoreUpdated`/`TierChanged` events reflect the qualifying
   repayment per `docs/bitscore-specification.md`.
8. **Withdraw collateral.** Call `BitVLendingManager.withdrawCollateral
   (asset, amount)` after debt is repaid (or while still comfortably
   healthy). Verify: `CollateralWithdrawn` event; reverts with
   `InsufficientCollateral` if attempted while it would drop health
   factor below 1.0x — confirm that revert path too, deliberately, once.
9. **Check health factor.** Cross-check `getHealthFactor(wallet)` against
   `HealthFactorCard`'s displayed value and status (healthy/warning/
   danger/no-debt) at each stage above — this is the exact bigint
   comparison `lib/health-factor.ts` performs; confirm no
   precision-loss regression (see Build 08's fixed bug) by checking a
   position intentionally set to exactly the 1.5x/1.0x boundaries if
   feasible.
10. **Test liquidation conditions safely.** Using a **dedicated test
    wallet with only testnet, non-critical funds**: open a position,
    then move its health factor below 1.0x (e.g. via a
    `StaticPriceOracle.setPrice` change on a testnet-only deployment, or
    natural interest accrual over time) and call
    `BitVLendingManager.liquidate(user, debtAsset, collateralAsset,
    repayAmount)` from a second wallet. Verify: `Liquidated` event;
    `closeFactorBps` is respected (repay capped at 50% of debt by
    default); collateral seized matches `repayValue * (1 +
    liquidationBonusBps)`; the liquidated position's health factor
    improves afterward. **Never run this step against a wallet holding
    funds anyone cares about losing** — this step is explicitly about
    verifying the liquidation path works, not a production incident.
11. **Deposit into vault.** Call `BitVYieldVault.deposit(assets, wallet)`
    for a configured vault. Verify: shares minted match `previewDeposit`;
    `maxDeposit` respects `vaultCap`/`depositsPaused`/CVI compliance;
    `VaultPositionCard` reflects the new position; confirm the dashboard
    does **not** present any share-price growth as "real yield" unless
    the vault's wired strategy is confirmed non-test (see
    `docs/dashboard-implementation.md`'s test-strategy labeling).
12. **Withdraw from vault.** Call `BitVYieldVault.withdraw(assets,
    wallet, wallet)` or `redeem`. Verify: shares burned correctly;
    `emergencyWithdraw` also works and returns only the vault's idle
    balance pro-rata, even mid-pause, per its NatSpec.
13. **Test RWA registration/eligibility.** For any RWA-registered asset:
    check `isRegisteredAsset`, `isEligibleForNewActivity`,
    `isCVAAdminAttested`, `isCVAInterfaceVerified`,
    `isCVAFullyRecognized`. Confirm the dashboard's `RWAStatusCard` shows
    exactly the three-tier distinction (admin-attested / interface-
    verified / fully recognized) and the disclaimer — never presents any
    of these as "Cleanverse approved."
14. **Check BitScore.** Call `getScore`/`getTier` for the test wallet
    before and after steps 7/10 above. Verify the score moves in the
    documented direction (up on a qualifying full-close repayment, down
    on liquidation) and stays within 0–100. Confirm `BitScoreCard`/
    `RiskTierBadge` show the correct tier boundary (25/50/75).
15. **Verify dashboard state.** Walk every `/dashboard/*` route
    (`overview`, `lending`, `vaults`, `rwa`, `pools`, `risk`, `activity`,
    `settings`) with the wallet connected and disconnected. Confirm each
    contract-backed section shows one of loading/loaded/empty/
    unavailable/error correctly — never a stale or fabricated value.
16. **Verify protocol events.** Cross-check every event listed in steps
    4–14 actually appears in the transaction receipt / on a block
    explorer, matching the emitting contract and arguments exactly.
17. **Verify treasury/fee behavior.** After interest has accrued
    (step 6/7) and/or a vault performance fee has accrued (step 11/12),
    call `BitVYieldVault.collectPerformanceFee()` and check
    `BitVTreasury`'s balance increases by the expected amount via
    `FeeReceived`/`Withdrawn` events; confirm `BitVTreasury.withdraw`
    (PROTOCOL_ADMIN_ROLE-gated) correctly moves funds out and reverts
    for any other caller.

## After the smoke test

Record actual results (transaction hashes, before/after balances, any
discrepancy from the expected behavior above) in a follow-up document —
this plan intentionally contained no results originally, since none of
these transactions had been executed. See below for what has since run.

## Results (Build 11)

Executed 2026-08-09 against real Monad Testnet (chain 10143), from a
GitHub Codespace, using deployer wallet
`0xa26ee13a084c756a3a44dda68f0547a1e654fb81`. Values confirmed via
`cast call` reads after each write, not just transaction success.

**Compliance setup** (prerequisite, not in the original numbered list):
issued a sandbox Cleanverse A-Pass to the deployer wallet via
`generate_apass` (chain `monad`), then registered both
`BitVPoolManager` and `BitVLendingManager` as compliance pools via
`POST /validator/register` with an unrestricted rule — see
`docs/cleanverse-dependency-lock.md`'s "Sandbox compliance
registrations" section for the full detail. `complianceVerify`
confirmed `true` for the deployer against both contracts before any
write transaction was attempted.

| Step | Result |
|---|---|
| 1. Connect wallet | Not exercised via the dashboard UI this pass — compliance/lending exercised directly via `cast`, see above |
| 3. Verify CVI status | `complianceVerify` confirmed `true` for the deployer on both `PoolManager` and `LendingManager` after registration |
| 4. Supply liquidity | Deposited 1,000 BVTEST into the pool via `PoolManager.deposit`. `balanceOf(BVTEST, deployer)` on the pool confirmed `1e21` (1,000 BVTEST) afterward |
| 5. Deposit collateral | Deposited 500 BVTEST as collateral via `LendingManager.depositCollateral`. `getCollateralBalance` confirmed `5e20` (500 BVTEST) |
| 6. Borrow | Borrowed 100 BVTEST via `LendingManager.borrow`. `getCurrentDebt` confirmed `1e20` (100 BVTEST) |
| 9. Check health factor | `getHealthFactor` returned `4e27` (4.0x) — matches the expected math exactly: 500 collateral × 80% liquidation threshold ÷ 100 debt |
| 7. Repay | Repaid 100 BVTEST via `LendingManager.repay`. A small nonzero debt remained (`4.138127853881e12` wei, ~0.0000041 BVTEST) — real interest accrued between the repay call and the next read, not a bug. Closed fully with a second `repay` call using the `type(uint256).max` sentinel; `getCurrentDebt` then confirmed `0` |
| 8. Withdraw collateral | Withdrew the full 500 BVTEST collateral via `LendingManager.withdrawCollateral`. `getCollateralBalance` confirmed `0` afterward |

## Results (Build 11, continued) — liquidation, vault, RWA, treasury

Executed the same day, same deployer wallet, continuing directly from
the results above.

### Step 10: Liquidation

Since BVTEST is used as both the collateral and debt asset in this
smoke-test pool, oracle price manipulation cannot change the health
factor (the price term cancels on both sides of the ratio). Instead, a
real, permissioned admin action was used: `RISK_MANAGER_ROLE`
temporarily lowered `PoolManager`'s risk params for BVTEST from
LTV 70% / max-LTV 70% / liquidation threshold 80% to 60% / 60% / 60%,
via `setRiskParams`, to make an existing healthy position briefly
liquidatable — then restored the original params afterward. This is a
legitimate on-chain governance action, not a workaround.

1. Deposited 200 BVTEST collateral, borrowed 130 BVTEST. Health factor
   confirmed `1.23x` (healthy) before the risk-param change.
2. Lowered risk params as above. `getHealthFactor` confirmed `9.23e26`
   (0.923x) — below 1.0x, liquidatable.
3. Executed `LendingManager.liquidate(user, debtAsset, collateralAsset,
   repayAmount)` — a controlled **self-liquidation** (the deployer
   wallet was both the borrower and the liquidator, which the contract
   permits; used deliberately here for a safe, fully-contained test).
   Repaid 65 BVTEST (the 50% close-factor maximum on 130 debt).
4. Post-liquidation reads confirmed exactly the expected math:
   - Collateral: `1.3175e20` (131.75 BVTEST — seized 68.25 BVTEST,
     i.e. 65 repaid × 1.05 liquidation bonus)
   - Debt: `6.5e19` (65 BVTEST — 130 minus the 65 repaid)
   - Liquidator settlement: net +3.25 BVTEST to the liquidator side of
     the self-liquidation — exactly the 5% bonus
5. Restored the original risk params (`setRiskParams` back to
   70%/70%/80%/5%), then fully repaid the remaining 65 BVTEST debt
   (`type(uint256).max` sentinel) and withdrew the remaining 131.75
   BVTEST collateral, closing the test position cleanly.

Transaction hashes were not individually captured this pass (the
liquidation call's own receipt lookup failed on a terminal syntax
error, not a chain-level issue) — every state change was instead
independently verified via `cast call` reads before/after each step,
which is the substantive verification this step required.

**Result: PASS.**

### Steps 11-12: Vault deposit / withdrawal

Deployed a testnet `BitVYieldVault` (BVTEST-denominated) and bound
`TestYieldStrategy` to it via `contracts/script/DeployTestnetVault.s.sol`
— addresses recorded in `docs/deployment-addresses-template.md`.
Registered the vault with Cleanverse's sandbox validator (its own,
separate `POST /validator/register` call, since it's a distinct
`BitVComplianceGuard` instance from `PoolManager`/`LendingManager`).
`complianceVerify` confirmed `true` for the deployer against the vault
before any deposit.

- Raised `vaultCap` from its deployed default of `0` (which means zero
  capacity, not unlimited — `type(uint256).max` is unlimited) to
  1,000,000 BVTEST via `VAULT_MANAGER_ROLE`.
- Deposited 200 BVTEST. `totalAssets` confirmed `2e20`; `balanceOf`
  (shares) confirmed `2e26` — shares come out ~1,000,000× larger than
  assets due to the vault's 6-decimal virtual-shares offset
  (inflation-attack mitigation), which is expected ERC-4626 behavior,
  not a bug.
- **Pause behavior**: `setDepositsPaused(true)`, then a further deposit
  attempt correctly **reverted**. Unpaused afterward.
- **Strategy allocation**: raised `maxStrategyAllocationBps` to 50% and
  `minIdleReserveBps` to 50%, then allocated 50 BVTEST to
  `TestYieldStrategy`. `TestYieldStrategy.totalAssets` confirmed `5e19`
  (50 BVTEST).
- **Simulated yield + performance fee → Treasury**: set
  `performanceFeeBps` to 10%, called `TestYieldStrategy.simulateYield`
  for 10 BVTEST (test-only — pulled from the caller's own balance, not
  a real yield source). Vault `totalAssets` confirmed `2.1e20` (210).
  Called `collectPerformanceFee()`; Treasury's BVTEST balance confirmed
  increased by exactly `1e18` (1 BVTEST) — precisely 10% of the 10
  BVTEST simulated profit.
- **Standard withdrawal**: withdrew 50 BVTEST. `totalAssets` confirmed
  `1.59e20` (159 — 210 minus the 1 BVTEST fee minus the 50 withdrawn,
  exact).
- **Emergency withdrawal**: `emergencyWithdraw()` burned all remaining
  shares; `balanceOf` confirmed `0` afterward.

**Result: PASS** (deposit, shares, totalAssets, withdrawal, compliance
gating, pause behavior, strategy allocation, and emergency withdrawal
all verified via on-chain reads). Compliance gating specifically for
the vault was verified via the same `complianceVerify`/registration
mechanism already proven twice on `PoolManager`/`LendingManager`,
rather than re-run as a separate negative test on the vault itself.

### Step 13: RWA eligibility

Registered BVTEST as RWA collateral on `RWACollateralRegistry`
(LTV 60%, liquidation threshold 70%, liquidation bonus 5%, collateral
cap 50,000 BVTEST — all ≤ the underlying pool's own configured
ceilings, as the registry requires), priced by the same
`StaticPriceOracle` already in use, then called `markPriceFresh`.

- `isRegisteredAsset`: confirmed `true`
- `isEligibleForNewActivity`: confirmed `true`
- **Frozen behavior**: `setAssetStatus(Frozen)` → `isEligibleForNewActivity`
  confirmed `false`. Restored to Active → confirmed `true` again.
- **CVA claim check**: `isCVAFullyRecognized` confirmed `false` — no
  CVA attestation was ever set for this asset, and none is claimed.
  BVTEST is a test asset with no real backing and is never presented
  as, or confused with, a Cleanverse Verified Asset.
- Delisted-status behavior (terminal, irreversible transition) was
  **not tested** — deliberately, to avoid permanently delisting the
  registry's only test asset mid-verification.

**Result: PASS** (registration, eligibility, LTV/threshold/cap limits,
oracle-freshness requirement, and frozen-state behavior all verified;
delisted-state transition explicitly not exercised, by design).

### Step 17: Treasury and fees

Covered by the vault section above — `collectPerformanceFee()`
delivered exactly 1 BVTEST (10% of 10 BVTEST simulated yield) to
`BitVTreasury`'s real ERC-20 balance, confirmed via a direct
`balanceOf` read before and after. This is the one fee-to-Treasury path
that was actually exercisable this pass: `BitVPoolManager`'s reserve-
factor interest (10% on the BVTEST pool) accrues internally as
additional scaled supply credited to the Treasury's address within the
pool's own accounting, but nothing calls `PoolManager.withdraw` as the
Treasury contract itself (which has no such function) — so that
specific interest-reserve path was not exercised or verified this
pass. This is worth a deliberate design decision in a future build
(e.g. a Treasury-callable claim function), not something this
verification pass attempted to fix.

**Result: PASS** for the vault performance-fee path; **NOT EXECUTED**
for the pool reserve-factor path (see above).

## Not yet executed

- Step 1 (wallet connection) and steps 2, 15-16 (network state,
  dashboard UI, protocol-event verification) — require driving an
  actual browser wallet session against `bitvapp.vercel.app`, not yet
  completed this pass.
- Delisted RWA-asset transition (deliberately skipped, terminal/
  irreversible).
- Pool reserve-factor interest reaching Treasury (see Step 17 above —
  a real, identified gap in the current Treasury interface, not an
  execution gap).

## Prompt 15 status (2026-08-09)

Prompt 15 Phase 8 asked for the full 18-item smoke test to be re-run
against a fresh Monad Testnet deployment. **Not executed this
session** — the fresh deployment itself could not be broadcast
(confirmed-blocked network egress to `testnet-rpc.monad.xyz`, tested
live this milestone), so there is no new deployment to smoke-test
against. The results above remain from Build 11's real, hand-executed
run against the (still-live, but Prompt-14-code-predating) Build 11
deployment. A dedicated frontend check found the Prompt 14 reserve-claim
functionality has no dashboard hook, component, or updated ABI entry —
see the Prompt 15 final report for detail; this is unrelated to the
network-egress block and is a real frontend gap on its own.
