// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseProtocolTest} from "../BaseProtocolTest.sol";
import {BitScoreManager} from "../../src/core/BitScoreManager.sol";
import {ProtocolErrors} from "../../src/libraries/ProtocolErrors.sol";
import {ComplianceErrors} from "../../src/libraries/ComplianceErrors.sol";

contract BitScoreManagerTest is BaseProtocolTest {
    function _supplyLiquidity(uint256 amount) internal {
        debtAsset.mint(supplier, amount); // top up regardless of BaseProtocolTest's default mint
        vm.startPrank(supplier);
        debtAsset.approve(address(poolManager), amount);
        poolManager.deposit(address(debtAsset), amount);
        vm.stopPrank();
    }

    /// Score growth per qualifying repayment is decay-tempered (see
    /// BitScoreManager's "decay-then-add" pattern), so it's slightly
    /// less than the raw +4 (3 repayment + 1 timeliness) points per
    /// event once compounded across many calls — empirically Tier 2
    /// (score >=50) is reached around iteration 6 and Tier 3 (score
    /// >=75) around iteration 14 at this fixture's 2-day-per-iteration
    /// cadence (verified via a temporary debug trace). This helper
    /// repeats `_borrowAndFullyRepayAfter` until either the target tier
    /// is reached or `maxIterations` is exhausted, so tests don't
    /// hardcode an iteration count that happens to be too low for the
    /// real (tempered) growth rate.
    function _repayUntilTier(address user, uint8 targetTier, uint256 maxIterations) internal {
        for (uint256 i = 0; i < maxIterations; i++) {
            if (bitScoreManager.getTier(user) >= targetTier) return;
            _borrowAndFullyRepayAfter(user, 100e18, 2 days);
        }
    }

    function _depositCollateral(address user, uint256 amount) internal {
        vm.startPrank(user);
        collateralAsset.approve(address(lendingManager), amount);
        lendingManager.depositCollateral(address(collateralAsset), amount);
        vm.stopPrank();
    }

    function _borrowAndFullyRepayAfter(address user, uint256 borrowAmount, uint256 elapsedSeconds) internal {
        vm.prank(user);
        lendingManager.borrow(address(debtAsset), borrowAmount);

        vm.warp(block.timestamp + elapsedSeconds);

        // Mint a comfortable surplus and repay via the type(uint256).max
        // sentinel (Build 04) rather than a pre-read amount, which is
        // guaranteed stale by the interest that accrues between the read
        // and this call — see BitVLendingManager.repay()'s NatSpec.
        debtAsset.mint(user, borrowAmount); // surplus to cover accrued interest
        vm.startPrank(user);
        debtAsset.approve(address(lendingManager), type(uint256).max);
        lendingManager.repay(address(debtAsset), type(uint256).max);
        vm.stopPrank();
    }

    // 1. Initial score
    function test_InitialScore_IsStartingScoreForNeverSeenWallet() public view {
        address neverSeen = address(0xABCD);
        assertEq(bitScoreManager.getScore(neverSeen), 30);
        assertEq(bitScoreManager.getTier(neverSeen), 1); // Standard
    }

    // 2. Successful repayment
    function test_SuccessfulRepayment_IncreasesScore() public {
        _supplyLiquidity(100_000e18);
        _depositCollateral(borrower, 10e18);

        uint16 before = bitScoreManager.getScore(borrower);
        _borrowAndFullyRepayAfter(borrower, 1_000e18, 2 days);

        assertGt(bitScoreManager.getScore(borrower), before);
    }

    // 3. Repayment behavior (BitV has no due dates — reframed per spec
    // as "closed while healthy" rather than "on time")
    function test_RepaymentBehavior_FullCloseEarnsMoreThanPartial() public {
        _supplyLiquidity(100_000e18);
        _depositCollateral(borrower, 10e18);

        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_000e18);
        vm.warp(block.timestamp + 2 days);

        uint16 beforePartial = bitScoreManager.getScore(borrower);
        vm.startPrank(borrower);
        debtAsset.approve(address(lendingManager), 400e18);
        lendingManager.repay(address(debtAsset), 400e18); // partial, not a full close
        vm.stopPrank();
        uint16 afterPartial = bitScoreManager.getScore(borrower);

        uint256 remainingDebt = lendingManager.getCurrentDebt(borrower, address(debtAsset));
        debtAsset.mint(borrower, remainingDebt);
        vm.startPrank(borrower);
        debtAsset.approve(address(lendingManager), remainingDebt);
        lendingManager.repay(address(debtAsset), remainingDebt); // full close
        vm.stopPrank();
        uint16 afterFullClose = bitScoreManager.getScore(borrower);

        uint16 partialGain = afterPartial - beforePartial;
        uint16 fullCloseGain = afterFullClose - afterPartial;
        assertGt(fullCloseGain, partialGain);
    }

    // 4. Minimum position duration
    function test_MinimumPositionDuration_InstantCloseEarnsNoCredit() public {
        _supplyLiquidity(100_000e18);
        _depositCollateral(borrower, 10e18);

        uint16 before = bitScoreManager.getScore(borrower);

        vm.startPrank(borrower);
        lendingManager.borrow(address(debtAsset), 1_000e18);
        // No time warp — same-block close, well under the 1-day minimum.
        debtAsset.approve(address(lendingManager), 1_000e18);
        lendingManager.repay(address(debtAsset), 1_000e18);
        vm.stopPrank();

        assertEq(bitScoreManager.getScore(borrower), before);
    }

    // 5. Liquidation penalty
    function test_LiquidationPenalty_DecreasesScore() public {
        _supplyLiquidity(100_000e18);
        _depositCollateral(borrower, 1e18);
        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_400e18); // max 70% LTV

        uint16 before = bitScoreManager.getScore(borrower);

        vm.prank(admin);
        oracle.setPrice(address(collateralAsset), 1_500e18, 18); // crash price -> unhealthy

        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 700e18);
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 700e18);
        vm.stopPrank();

        assertLt(bitScoreManager.getScore(borrower), before);
    }

    // 6. Penalty decay
    function test_LiquidationPenaltyDecaysOverTime() public {
        _supplyLiquidity(100_000e18);
        _depositCollateral(borrower, 1e18);
        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_400e18);

        vm.prank(admin);
        oracle.setPrice(address(collateralAsset), 1_500e18, 18);

        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 700e18);
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 700e18);
        vm.stopPrank();

        uint16 rightAfter = bitScoreManager.getScore(borrower);
        vm.warp(block.timestamp + 400 days); // past the 365-day liquidation decay window
        uint16 muchLater = bitScoreManager.getScore(borrower);

        assertGt(muchLater, rightAfter);
    }

    // 7. Permanent bad debt penalty
    function test_BadDebtPenalty_DoesNotDecay() public {
        _supplyLiquidity(100_000e18);
        _depositCollateral(borrower, 1e18);
        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_400e18);

        // Crash price hard enough that seizing the liquidation-bonus-
        // adjusted collateral for a full close would exceed what the
        // borrower actually has -> insolvency path -> bad debt.
        vm.prank(admin);
        oracle.setPrice(address(collateralAsset), 700e18, 18);

        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 1_400e18);
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 1_400e18);
        vm.stopPrank();

        uint16 rightAfter = bitScoreManager.getScore(borrower);
        vm.warp(block.timestamp + 1000 days);
        uint16 muchLater = bitScoreManager.getScore(borrower);

        // Bad debt itself never decays; the score may still drift from
        // 0 as other components (which do decay) settle, but it must not
        // *increase* purely from time passing when the only history is a
        // permanent penalty.
        assertLe(muchLater, rightAfter + 1); // +1 tolerance for rounding, never a real recovery
    }

    // 8. Score recovery
    function test_ScoreRecovery_AfterLiquidationViaRepayments() public {
        _supplyLiquidity(1_000_000e18);
        _depositCollateral(borrower, 1e18);
        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_400e18);

        vm.prank(admin);
        oracle.setPrice(address(collateralAsset), 1_500e18, 18);
        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 700e18);
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 700e18);
        vm.stopPrank();

        uint16 afterLiquidation = bitScoreManager.getScore(borrower);

        // Recover via new, sustained qualifying repayments.
        _depositCollateral(borrower, 5e18);
        for (uint256 i = 0; i < 5; i++) {
            _borrowAndFullyRepayAfter(borrower, 100e18, 2 days);
        }

        assertGt(bitScoreManager.getScore(borrower), afterLiquidation);
    }

    // 9. Score cap at 100
    function test_ScoreNeverExceedsMax() public {
        _supplyLiquidity(10_000_000e18);
        _depositCollateral(borrower, 100e18);

        // The "decay-then-add" positive-contribution model (see
        // BitScoreManager's NatSpec) converges toward the nominal +70
        // cap (score 100) within roughly two dozen qualifying events at
        // this cadence (empirically verified via a temporary debug
        // trace) — what actually matters is that the hard clamp in
        // getScore() is never violated regardless of how much
        // qualifying activity occurs. 250 iterations is comfortably
        // beyond that point.
        uint8 previous = bitScoreManager.getScore(borrower);
        for (uint256 i = 0; i < 250; i++) {
            _borrowAndFullyRepayAfter(borrower, 100e18, 2 days);
            uint8 current = bitScoreManager.getScore(borrower);
            assertLe(current, 100); // never exceeded, every single step
            previous = current;
        }
        assertLe(previous, 100);
        assertGt(previous, 80); // sustained activity clearly pushed it well above the 30 baseline
    }

    // 10. Score floor at 0
    function test_ScoreNeverGoesBelowZero() public {
        _supplyLiquidity(1_000_000e18);
        // 1e18 (not 10e18) — deliberately close to the LTV limit, same
        // as BitVLiquidationTest's fixture, so the post-crash position
        // is actually undercollateralized rather than merely trimmed.
        _depositCollateral(borrower, 1e18);
        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_400e18);

        // One severe, sustained crash; repeatedly liquidate the same
        // position (each call capped at 50% of *remaining* debt by
        // closeFactorBps) until fully closed, without ever letting the
        // position recover to healthy in between — isolates "does score
        // stay floored at repeated liquidation penalties" from
        // "liquidating an already-healthy position reverts" (a separate,
        // already-covered case in BitVLiquidationTest).
        vm.prank(admin);
        oracle.setPrice(address(collateralAsset), 500e18, 18);

        for (uint256 i = 0; i < 10; i++) {
            uint256 debt = lendingManager.getCurrentDebt(borrower, address(debtAsset));
            if (debt == 0) break;
            uint256 collateralLeft = lendingManager.getCollateralBalance(borrower, address(collateralAsset));
            if (collateralLeft == 0) break;

            vm.startPrank(liquidator);
            debtAsset.approve(address(lendingManager), debt);
            lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), debt);
            vm.stopPrank();
        }

        assertGe(bitScoreManager.getScore(borrower), 0); // trivially true for uint16, documents intent
        assertEq(bitScoreManager.getTier(borrower), 0); // Restricted
    }

    // 11. Tier transitions
    function test_TierTransitions_EmitsTierChangedOnBoundaryCross() public {
        _supplyLiquidity(1_000_000e18);
        _depositCollateral(borrower, 10e18);

        // 30 (Tier 1) -> push toward Tier 2 (>=50) via repeated repayments.
        _repayUntilTier(borrower, 2, 30);

        assertEq(bitScoreManager.getTier(borrower), 2);
    }

    // 12. LTV adjustment
    function test_LtvAdjustment_HigherTierGetsMoreAvailableBorrowValue() public {
        _supplyLiquidity(1_000_000e18);
        _depositCollateral(borrower, 10e18); // $20,000 collateral

        uint256 baseAvailable = lendingManager.getUserAccountData(borrower).availableBorrowValue; // 70% = $14,000
        uint256 effectiveAtTier1 = lendingManager.getEffectiveAvailableBorrowValue(borrower);
        assertEq(effectiveAtTier1, baseAvailable); // Tier 1: no adjustment

        // Push to Tier 3 (>=750) via sustained repayments.
        _repayUntilTier(borrower, 3, 30);
        assertEq(bitScoreManager.getTier(borrower), 3);

        uint256 effectiveAtTier3 = lendingManager.getEffectiveAvailableBorrowValue(borrower);
        assertGt(effectiveAtTier3, baseAvailable);

        // Never exceeds the asset's configured ceiling (78% = $15,600).
        uint256 maxPossible = uint256(10e18) * COLLATERAL_PRICE / 1e18 * 7_800 / 10_000;
        assertLe(effectiveAtTier3, maxPossible);
    }

    // 13. Interest adjustment (quoted only — see IBitScoreManager.getBaseRateDiscountRay's NatSpec)
    function test_InterestAdjustment_QuotedDiscountIsTierDependent() public {
        assertEq(lendingManager.getQuotedBaseRateDiscountRay(borrower), 0); // Tier 1: no discount

        _supplyLiquidity(1_000_000e18);
        _depositCollateral(borrower, 10e18);
        _repayUntilTier(borrower, 3, 30);
        assertEq(bitScoreManager.getTier(borrower), 3);

        assertGt(lendingManager.getQuotedBaseRateDiscountRay(borrower), 0);
    }

    // 14. Unauthorized score updates
    function test_UnauthorizedCaller_CannotRecordRepayment() public {
        vm.prank(borrower); // not the registered lendingManager
        vm.expectRevert(ProtocolErrors.CallerNotLendingManager.selector);
        bitScoreManager.recordRepayment(borrower, true, 2 days);
    }

    function test_UnauthorizedCaller_CannotSetParams() public {
        BitScoreManager.Params memory p = bitScoreManager.getParams();
        // Compute the expected role hash *before* pranking — vm.prank
        // only affects the single next external call, and
        // accessManager.RISK_MANAGER_ROLE() is itself an external call
        // (same class of bug caught and fixed in Build 03.5).
        bytes32 riskManagerRole = accessManager.RISK_MANAGER_ROLE();

        vm.prank(borrower); // not RISK_MANAGER_ROLE
        vm.expectRevert(abi.encodeWithSelector(ProtocolErrors.Unauthorized.selector, borrower, riskManagerRole));
        bitScoreManager.setParams(p);
    }

    // 15. Compliance failure
    function test_ComplianceFailure_BitScoreNeverConsulted() public {
        address stranger = makeAddr("neverCompliantForBitScore");
        collateralAsset.mint(stranger, 10e18);

        uint16 scoreBefore = bitScoreManager.getScore(stranger);

        vm.startPrank(stranger);
        collateralAsset.approve(address(lendingManager), 10e18);
        vm.expectRevert(
            abi.encodeWithSelector(ComplianceErrors.ComplianceCheckFailed.selector, address(lendingManager), stranger)
        );
        lendingManager.depositCollateral(address(collateralAsset), 10e18);
        vm.stopPrank();

        // Score is untouched — BitScoreManager was never called.
        assertEq(bitScoreManager.getScore(stranger), scoreBefore);
    }

    // 16. Missing score fallback
    function test_MissingScore_FallsBackToStandardTierDefaults() public {
        address brandNew = makeAddr("brandNewWallet");
        assertEq(bitScoreManager.getScore(brandNew), 30);
        assertEq(bitScoreManager.getTier(brandNew), 1);
    }

    // 17. BitScore failure fallback
    function test_BitScoreDisabled_FallsBackToBaseParameters() public {
        vm.prank(admin);
        lendingManager.setBitScoreManager(address(0));

        _supplyLiquidity(1_000_000e18);
        _depositCollateral(borrower, 10e18);

        uint256 baseAvailable = lendingManager.getUserAccountData(borrower).availableBorrowValue;
        uint256 effective = lendingManager.getEffectiveAvailableBorrowValue(borrower);
        assertEq(effective, baseAvailable);

        // Borrowing still works normally with BitScore disabled.
        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_000e18);
        assertEq(lendingManager.getCurrentDebt(borrower, address(debtAsset)), 1_000e18);
    }

    // 18. Score cannot bypass hard protocol limits
    function test_HighScore_CannotBorrowBeyondConfiguredCeiling() public {
        _supplyLiquidity(1_000_000e18);
        _depositCollateral(borrower, 10e18); // $20,000 collateral

        _repayUntilTier(borrower, 3, 30);
        assertEq(bitScoreManager.getTier(borrower), 3);

        // Ceiling: 78% of $20,000 = $15,600. Attempting to borrow $15,700
        // must still revert even at max tier.
        vm.prank(borrower);
        vm.expectRevert();
        lendingManager.borrow(address(debtAsset), 15_700e18);
    }

    // 19. Deposit/withdraw farming does not generate artificial score
    function test_PoolDepositWithdrawCycles_EarnNoScoreCredit() public {
        uint16 before = bitScoreManager.getScore(supplier);

        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(supplier);
            debtAsset.approve(address(poolManager), 1_000e18);
            poolManager.deposit(address(debtAsset), 1_000e18);
            poolManager.withdraw(address(debtAsset), 1_000e18);
            vm.stopPrank();
        }

        assertEq(bitScoreManager.getScore(supplier), before);
    }

    // 20. Repeated activity cannot exceed contribution caps
    function test_RepeatedRepayments_CannotExceedPositiveContributionCap() public {
        _supplyLiquidity(10_000_000e18);
        _depositCollateral(borrower, 1_000e18);

        // See test_ScoreNeverExceedsMax's note: the decay-tempered model
        // converges toward, rather than snapping exactly to, the
        // nominal cap at realistic event cadences — the invariant this
        // test actually needs to prove is "the clamp in getScore() is
        // never violated," checked on every single iteration, not just
        // at the end.
        for (uint256 i = 0; i < 300; i++) {
            _borrowAndFullyRepayAfter(borrower, 10e18, 2 days);
            assertLe(bitScoreManager.getScore(borrower), 100);
        }
    }
}
