# BitV Testnet Smoke-Test Plan (Build 09)

This is a manual test sequence to run **after** a real deployment exists
on Monad Testnet and `services/contracts/addresses.ts` has been populated
with the resulting addresses — see `docs/deployment-readiness.md` for
what must be true before that deployment happens. **None of the steps
below have been executed.** This document does not claim any transaction
succeeded; it defines what "succeeded" should look like when someone
actually runs it.

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
this plan intentionally contains no results, since none of these
transactions have been executed.
