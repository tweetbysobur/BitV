// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseTest } from "../BaseTest.sol";
import { IIdentityOracle } from "../../src/interfaces/IIdentityOracle.sol";
import { Errors } from "../../src/libraries/Errors.sol";
import { WadRayMath } from "../../src/libraries/WadRayMath.sol";

contract LendingManagerTest is BaseTest {
    function _seedLiquidity() internal {
        vm.startPrank(alice);
        usdc.approve(address(poolManager), 500_000e6);
        poolManager.supply(address(usdc), 500_000e6);
        vm.stopPrank();
    }

    function test_borrow_againstCollateral_succeeds() public {
        _seedLiquidity();

        vm.startPrank(bob);
        weth.approve(address(lendingManager), 10e18);
        lendingManager.depositCollateral(address(weth), 10e18);
        // 10 WETH * $3000 * 75% LTV = $22,500 borrowing power
        lendingManager.borrow(address(usdc), 20_000e6);
        vm.stopPrank();

        assertEq(lendingManager.debtOf(bob, address(usdc)), 20_000e6);
        assertEq(usdc.balanceOf(bob), 1_000_000e6 + 20_000e6);
    }

    function test_borrow_revertsWhenExceedingBorrowingPower() public {
        _seedLiquidity();

        vm.startPrank(bob);
        weth.approve(address(lendingManager), 1e18);
        lendingManager.depositCollateral(address(weth), 1e18); // $3,000 * 75% = $2,250 power

        vm.expectRevert(); // CreditLineExceeded
        lendingManager.borrow(address(usdc), 3_000e6);
        vm.stopPrank();
    }

    function test_borrow_revertsForUnverifiedIdentity() public {
        _seedLiquidity();
        identityOracle.setStatus(bob, IIdentityOracle.IdentityStatus.Unregistered);

        vm.startPrank(bob);
        weth.approve(address(lendingManager), 10e18);
        lendingManager.depositCollateral(address(weth), 10e18);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.IdentityNotRegistered.selector, bob)
        );
        lendingManager.borrow(address(usdc), 1_000e6);
        vm.stopPrank();
    }

    function test_repay_reducesDebt() public {
        _seedLiquidity();

        vm.startPrank(bob);
        weth.approve(address(lendingManager), 10e18);
        lendingManager.depositCollateral(address(weth), 10e18);
        lendingManager.borrow(address(usdc), 10_000e6);

        usdc.approve(address(lendingManager), 10_000e6);
        uint256 repaid = lendingManager.repay(address(usdc), 10_000e6, bob);
        vm.stopPrank();

        assertEq(repaid, 10_000e6);
        assertEq(lendingManager.debtOf(bob, address(usdc)), 0);
    }

    function test_repay_capsAtOutstandingDebt() public {
        _seedLiquidity();

        vm.startPrank(bob);
        weth.approve(address(lendingManager), 10e18);
        lendingManager.depositCollateral(address(weth), 10e18);
        lendingManager.borrow(address(usdc), 10_000e6);

        usdc.approve(address(lendingManager), 50_000e6);
        uint256 repaid = lendingManager.repay(address(usdc), 50_000e6, bob);
        vm.stopPrank();

        // Only the actual $10,000 debt is pulled, not the requested $50,000 —
        // overpayment must never be silently accepted as a donation.
        assertEq(repaid, 10_000e6);
        assertEq(usdc.balanceOf(bob), 1_000_000e6);
    }

    function test_withdrawCollateral_revertsIfWouldBreachHealthFactor() public {
        _seedLiquidity();

        vm.startPrank(bob);
        weth.approve(address(lendingManager), 10e18);
        lendingManager.depositCollateral(address(weth), 10e18);
        lendingManager.borrow(address(usdc), 20_000e6);

        vm.expectRevert();
        lendingManager.withdrawCollateral(address(weth), 9e18);
        vm.stopPrank();
    }

    function test_healthFactor_infiniteWithNoDebt() public {
        vm.startPrank(bob);
        weth.approve(address(lendingManager), 5e18);
        lendingManager.depositCollateral(address(weth), 5e18);
        vm.stopPrank();

        assertEq(lendingManager.healthFactor(bob), type(uint256).max);
    }

    function test_liquidate_unhealthyPosition() public {
        _seedLiquidity();

        vm.startPrank(bob);
        weth.approve(address(lendingManager), 10e18);
        lendingManager.depositCollateral(address(weth), 10e18);
        lendingManager.borrow(address(usdc), 20_000e6); // HF healthy at $3000/WETH
        vm.stopPrank();

        // Crash WETH price so bob's position becomes liquidatable:
        // collateral@liqThreshold = 10 * price * 80%; debt = $20,000.
        // At $2,000/WETH: 10*2000*0.8 = $16,000 < $20,000 debt -> HF < 1.
        vm.prank(admin);
        priceOracle.setPrice(address(weth), 2_000e18);

        uint256 hf = lendingManager.healthFactor(bob);
        assertLt(hf, WadRayMath.WAD);

        uint256 debtBefore = lendingManager.debtOf(bob, address(usdc));
        uint256 maxRepay = debtBefore / 2; // 50% close factor

        vm.startPrank(liquidator);
        usdc.approve(address(lendingManager), maxRepay);
        uint256 seized = lendingManager.liquidate(bob, address(usdc), address(weth), maxRepay);
        vm.stopPrank();

        assertEq(lendingManager.debtOf(bob, address(usdc)), debtBefore - maxRepay);
        assertGt(seized, 0);
        assertEq(weth.balanceOf(liquidator), seized);
    }

    function test_liquidate_revertsOnHealthyPosition() public {
        _seedLiquidity();

        vm.startPrank(bob);
        weth.approve(address(lendingManager), 10e18);
        lendingManager.depositCollateral(address(weth), 10e18);
        lendingManager.borrow(address(usdc), 1_000e6);
        vm.stopPrank();

        vm.startPrank(liquidator);
        usdc.approve(address(lendingManager), 1_000e6);
        vm.expectRevert();
        lendingManager.liquidate(bob, address(usdc), address(weth), 500e6);
        vm.stopPrank();
    }

    function test_liquidate_revertsAboveCloseFactor() public {
        _seedLiquidity();

        vm.startPrank(bob);
        weth.approve(address(lendingManager), 10e18);
        lendingManager.depositCollateral(address(weth), 10e18);
        lendingManager.borrow(address(usdc), 20_000e6);
        vm.stopPrank();

        vm.prank(admin);
        priceOracle.setPrice(address(weth), 2_000e18);

        uint256 debt = lendingManager.debtOf(bob, address(usdc));

        vm.startPrank(liquidator);
        usdc.approve(address(lendingManager), debt);
        vm.expectRevert(); // exceeds 50% close factor
        lendingManager.liquidate(bob, address(usdc), address(weth), debt);
        vm.stopPrank();
    }
}
