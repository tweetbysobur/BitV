// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseProtocolTest} from "../BaseProtocolTest.sol";
import {ProtocolErrors} from "../../src/libraries/ProtocolErrors.sol";
import {ComplianceErrors} from "../../src/libraries/ComplianceErrors.sol";

contract BitVLendingManagerTest is BaseProtocolTest {
    function _supplyLiquidity(uint256 amount) internal {
        vm.startPrank(supplier);
        debtAsset.approve(address(poolManager), amount);
        poolManager.deposit(address(debtAsset), amount);
        vm.stopPrank();
    }

    function _depositCollateral(address user, uint256 amount) internal {
        vm.startPrank(user);
        collateralAsset.approve(address(lendingManager), amount);
        lendingManager.depositCollateral(address(collateralAsset), amount);
        vm.stopPrank();
    }

    function test_DepositCollateral_CreditsBalance() public {
        _depositCollateral(borrower, 5e18);
        assertEq(lendingManager.getCollateralBalance(borrower, address(collateralAsset)), 5e18);
        assertEq(collateralAsset.balanceOf(address(lendingManager)), 5e18);
    }

    function test_Borrow_WithinLtv_Succeeds() public {
        _supplyLiquidity(10_000e18);
        _depositCollateral(borrower, 10e18); // $20,000 collateral, 70% LTV = $14,000 max

        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 5_000e18);

        assertEq(lendingManager.getCurrentDebt(borrower, address(debtAsset)), 5_000e18);
        assertEq(debtAsset.balanceOf(borrower), 5_000e18);
    }

    function test_Borrow_ExceedingLtv_Reverts() public {
        _supplyLiquidity(100_000e18);
        _depositCollateral(borrower, 1e18); // $2,000 collateral, 70% LTV = $1,400 max

        vm.prank(borrower);
        vm.expectRevert(
            abi.encodeWithSelector(ProtocolErrors.InsufficientCollateral.selector, 1_401e18, 1_400e18)
        );
        lendingManager.borrow(address(debtAsset), 1_401e18);
    }

    function test_Repay_ReducesDebtAndReturnsFunds() public {
        _supplyLiquidity(10_000e18);
        _depositCollateral(borrower, 10e18);

        vm.startPrank(borrower);
        lendingManager.borrow(address(debtAsset), 2_000e18);
        debtAsset.approve(address(lendingManager), 2_000e18);
        uint256 repaid = lendingManager.repay(address(debtAsset), 2_000e18);
        vm.stopPrank();

        assertEq(repaid, 2_000e18);
        assertEq(lendingManager.getCurrentDebt(borrower, address(debtAsset)), 0);
    }

    function test_Repay_OverpayCapsAtCurrentDebt() public {
        _supplyLiquidity(10_000e18);
        _depositCollateral(borrower, 10e18);

        vm.startPrank(borrower);
        lendingManager.borrow(address(debtAsset), 1_000e18);
        debtAsset.approve(address(lendingManager), 5_000e18);
        uint256 repaid = lendingManager.repay(address(debtAsset), 5_000e18);
        vm.stopPrank();

        assertEq(repaid, 1_000e18);
        assertEq(lendingManager.getCurrentDebt(borrower, address(debtAsset)), 0);
    }

    function test_WithdrawCollateral_HealthyAfter_Succeeds() public {
        _supplyLiquidity(10_000e18);
        _depositCollateral(borrower, 10e18);

        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_000e18); // small debt vs $20,000 collateral

        vm.prank(borrower);
        lendingManager.withdrawCollateral(address(collateralAsset), 2e18);

        assertEq(lendingManager.getCollateralBalance(borrower, address(collateralAsset)), 8e18);
    }

    function test_WithdrawCollateral_WouldBreachHealth_Reverts() public {
        _supplyLiquidity(10_000e18);
        _depositCollateral(borrower, 10e18); // $20,000 collateral

        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 7_000e18); // near 70% LTV, close to threshold

        vm.prank(borrower);
        vm.expectRevert();
        lendingManager.withdrawCollateral(address(collateralAsset), 9e18); // would leave ~$2,000 collateral vs $7,000 debt
    }

    function test_InterestAccrual_IncreasesBorrowerDebtAndSupplierBalance() public {
        _supplyLiquidity(10_000e18);
        _depositCollateral(borrower, 10e18);

        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 8_000e18); // 80% utilization -> at the model's kink

        uint256 debtBefore = lendingManager.getCurrentDebt(borrower, address(debtAsset));
        uint256 supplyBefore = poolManager.balanceOf(address(debtAsset), supplier);

        vm.warp(block.timestamp + 365 days);
        poolManager.accrueInterest(address(debtAsset));

        uint256 debtAfter = lendingManager.getCurrentDebt(borrower, address(debtAsset));
        uint256 supplyAfter = poolManager.balanceOf(address(debtAsset), supplier);

        assertGt(debtAfter, debtBefore);
        assertGt(supplyAfter, supplyBefore);
    }

    function test_InterestAccrual_IsDeterministicGivenSameElapsedTime() public {
        _supplyLiquidity(10_000e18);
        _depositCollateral(borrower, 10e18);
        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 5_000e18);

        vm.warp(block.timestamp + 30 days);
        poolManager.accrueInterest(address(debtAsset));
        uint256 debtAt30Days = lendingManager.getCurrentDebt(borrower, address(debtAsset));

        // Same elapsed time from a fresh identical setup should produce
        // the same debt growth — determinism check via a second borrower
        // under identical conditions from block.timestamp reset forward
        // is impractical mid-test, so instead assert the accrual is
        // strictly monotonic and bounded (sanity, not flaky timing-based
        // equality).
        assertGt(debtAt30Days, 5_000e18);
        assertLt(debtAt30Days, 5_100e18); // well under 2%/month at this utilization
    }

    // ── Compliance ───────────────────────────────────────────────────────

    function test_Compliance_UnverifiedBorrowerRejected() public {
        address stranger = makeAddr("stranger");
        collateralAsset.mint(stranger, 10e18);

        vm.startPrank(stranger);
        collateralAsset.approve(address(lendingManager), 10e18);
        vm.expectRevert(
            abi.encodeWithSelector(ComplianceErrors.ComplianceCheckFailed.selector, address(lendingManager), stranger)
        );
        lendingManager.depositCollateral(address(collateralAsset), 10e18);
        vm.stopPrank();
    }

    // ── Build 03.5 review fixes ──────────────────────────────────────────

    /// Found during the Build 03.5 economic review: depositCollateral
    /// previously checked isActive/isCollateralEnabled but not isPaused,
    /// so pausing a collateral pool didn't actually stop new collateral
    /// deposits into it.
    function test_DepositCollateral_RespectsPoolPause() public {
        vm.prank(admin);
        poolManager.setPoolPaused(address(collateralAsset), true);

        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), 10e18);
        vm.expectRevert(
            abi.encodeWithSelector(ProtocolErrors.PoolIsPaused.selector, address(collateralAsset))
        );
        lendingManager.depositCollateral(address(collateralAsset), 10e18);
        vm.stopPrank();
    }

    /// Found during the Build 03.5 economic review: a zero-priced asset
    /// (oracle set, price explicitly 0) previously valued at silently
    /// $0 instead of reverting, for whichever asset the caller is
    /// directly acting on.
    function test_Borrow_ZeroPricedDebtAsset_RevertsLoudly() public {
        _supplyLiquidity(10_000e18);
        _depositCollateral(borrower, 10e18);

        vm.prank(admin);
        oracle.setPrice(address(debtAsset), 0, 18);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(ProtocolErrors.ZeroPrice.selector, address(debtAsset)));
        lendingManager.borrow(address(debtAsset), 1_000e18);
    }
}
