// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseProtocolTest} from "../BaseProtocolTest.sol";
import {ProtocolErrors} from "../../src/libraries/ProtocolErrors.sol";

contract BitVLiquidationTest is BaseProtocolTest {
    function _supplyLiquidity(uint256 amount) internal {
        vm.startPrank(supplier);
        debtAsset.approve(address(poolManager), amount);
        poolManager.deposit(address(debtAsset), amount);
        vm.stopPrank();
    }

    /// Deposits 1 collateral unit ($2,000 at setUp's price) and borrows
    /// exactly the 70% LTV max ($1,400), leaving the position right at
    /// the LTV boundary but still healthy against the 80% liquidation
    /// threshold ($1,600 > $1,400 debt).
    function _openMaxLtvPosition() internal {
        _supplyLiquidity(100_000e18);

        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), 1e18);
        lendingManager.depositCollateral(address(collateralAsset), 1e18);
        lendingManager.borrow(address(debtAsset), 1_400e18);
        vm.stopPrank();
    }

    function _crashCollateralPrice() internal {
        // $2,000 -> $1,500: liquidation-threshold-weighted collateral
        // value drops to $1,200, below the $1,400 debt -> health factor < 1.
        vm.prank(admin);
        oracle.setPrice(address(collateralAsset), 1_500e18, 18);
    }

    function test_HealthyPosition_CannotBeLiquidated() public {
        _openMaxLtvPosition(); // healthy: $1,600 liq-threshold value > $1,400 debt

        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 1_400e18);
        vm.expectRevert(); // PositionIsHealthy
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 700e18);
        vm.stopPrank();
    }

    function test_UnhealthyPosition_CanBeLiquidated() public {
        _openMaxLtvPosition();
        _crashCollateralPrice();

        assertLt(lendingManager.getHealthFactor(borrower), 1e27);

        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 700e18);
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 700e18);
        vm.stopPrank();

        // Debt reduced by exactly the repaid amount.
        assertEq(lendingManager.getCurrentDebt(borrower, address(debtAsset)), 1_400e18 - 700e18);
    }

    function test_PartialLiquidation_RespectsCloseFactor() public {
        _openMaxLtvPosition();
        _crashCollateralPrice();

        // Close factor is 50% (default) -> max single-call repay is 700e18
        // even though the liquidator offers to repay the full 1,400e18.
        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 1_400e18);
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 1_400e18);
        vm.stopPrank();

        assertEq(lendingManager.getCurrentDebt(borrower, address(debtAsset)), 1_400e18 - 700e18);
    }

    function test_LiquidationBonus_SeizesExtraCollateral() public {
        _openMaxLtvPosition();
        _crashCollateralPrice();

        uint256 repayAmount = 700e18; // $700 of debt
        // seizeValue = $700 * 1.05 (5% bonus) = $735
        // seizeAmount = $735 / $1,500 per collateral unit = 0.49e18
        uint256 expectedSeize = 0.49e18;

        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), repayAmount);
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), repayAmount);
        vm.stopPrank();

        assertEq(collateralAsset.balanceOf(liquidator), expectedSeize);
        assertEq(lendingManager.getCollateralBalance(borrower, address(collateralAsset)), 1e18 - expectedSeize);
    }

    function test_DebtReduction_MatchesRepaidAmountExactly() public {
        _openMaxLtvPosition();
        _crashCollateralPrice();

        uint256 debtBefore = lendingManager.getCurrentDebt(borrower, address(debtAsset));

        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 300e18);
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 300e18);
        vm.stopPrank();

        uint256 debtAfter = lendingManager.getCurrentDebt(borrower, address(debtAsset));
        assertEq(debtBefore - debtAfter, 300e18);
    }

    function test_NoOutstandingDebt_Reverts() public {
        _supplyLiquidity(100_000e18);
        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), 1e18);
        lendingManager.depositCollateral(address(collateralAsset), 1e18);
        vm.stopPrank();
        // Never borrowed anything.

        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 100e18);
        vm.expectRevert(
            abi.encodeWithSelector(ProtocolErrors.NoOutstandingDebt.selector, address(debtAsset))
        );
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 100e18);
        vm.stopPrank();
    }

    function test_RepeatedLiquidation_SecondCallOperatesOnReducedDebt() public {
        _openMaxLtvPosition();
        _crashCollateralPrice();

        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 1_400e18);
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 700e18);

        // Position is still unhealthy after the first partial liquidation
        // (collateral seized reduces the numerator too) — a second call
        // must operate correctly on the now-reduced debt, not double-count.
        uint256 debtBeforeSecond = lendingManager.getCurrentDebt(borrower, address(debtAsset));
        if (lendingManager.getHealthFactor(borrower) < 1e27) {
            lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), debtBeforeSecond);
            assertLt(lendingManager.getCurrentDebt(borrower, address(debtAsset)), debtBeforeSecond);
        }
        vm.stopPrank();
    }
}
