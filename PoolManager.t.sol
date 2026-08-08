// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseTest } from "../BaseTest.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { Errors } from "../../src/libraries/Errors.sol";
import { WadRayMath } from "../../src/libraries/WadRayMath.sol";

contract PoolManagerTest is BaseTest {
    function test_supply_creditsScaledBalance() public {
        vm.startPrank(alice);
        usdc.approve(address(poolManager), 10_000e6);
        poolManager.supply(address(usdc), 10_000e6);
        vm.stopPrank();

        assertEq(poolManager.balanceOf(address(usdc), alice), 10_000e6);
        assertEq(poolManager.totalLiquidity(address(usdc)), 10_000e6);
        assertEq(usdc.balanceOf(address(poolManager)), 10_000e6);
    }

    function test_withdraw_returnsUnderlying() public {
        vm.startPrank(alice);
        usdc.approve(address(poolManager), 10_000e6);
        poolManager.supply(address(usdc), 10_000e6);

        uint256 withdrawn = poolManager.withdraw(address(usdc), 4_000e6);
        vm.stopPrank();

        assertEq(withdrawn, 4_000e6);
        assertEq(poolManager.balanceOf(address(usdc), alice), 6_000e6);
        assertEq(usdc.balanceOf(alice), 1_000_000e6 - 6_000e6);
    }

    function test_withdraw_maxUint_withdrawsFullBalance() public {
        vm.startPrank(alice);
        usdc.approve(address(poolManager), 10_000e6);
        poolManager.supply(address(usdc), 10_000e6);

        uint256 withdrawn = poolManager.withdraw(address(usdc), type(uint256).max);
        vm.stopPrank();

        assertEq(withdrawn, 10_000e6);
        assertEq(poolManager.balanceOf(address(usdc), alice), 0);
    }

    function test_withdraw_revertsAboveBalance() public {
        vm.startPrank(alice);
        usdc.approve(address(poolManager), 10_000e6);
        poolManager.supply(address(usdc), 10_000e6);

        vm.expectRevert(abi.encodeWithSelector(Errors.AmountExceedsBalance.selector, 20_000e6, 10_000e6));
        poolManager.withdraw(address(usdc), 20_000e6);
        vm.stopPrank();
    }

    function test_supply_revertsWhenAssetNotListed() public {
        vm.startPrank(alice);
        vm.expectRevert();
        poolManager.supply(address(0xdead), 1e18);
        vm.stopPrank();
    }

    /// @dev Receipt-token transfer must move the redeemable claim — this is
    ///      the specific bug class the accounting design deliberately avoids
    ///      (see the NatSpec in `PoolManagerStorage`): a supplier who
    ///      transfers their aToken to another address must lose the ability
    ///      to withdraw, and the recipient must gain it, with total supply
    ///      unaffected.
    function test_receiptTokenTransfer_movesWithdrawableClaim() public {
        vm.startPrank(alice);
        usdc.approve(address(poolManager), 10_000e6);
        poolManager.supply(address(usdc), 10_000e6);

        address aToken = poolManager.getPool(address(usdc)).aToken;
        vm.stopPrank();

        vm.prank(alice);
        (bool ok,) = aToken.call(abi.encodeWithSignature("transfer(address,uint256)", bob, 10_000e6));
        assertTrue(ok);

        assertEq(poolManager.balanceOf(address(usdc), alice), 0);
        assertEq(poolManager.balanceOf(address(usdc), bob), 10_000e6);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.AmountExceedsBalance.selector, 1e6, 0));
        poolManager.withdraw(address(usdc), 1e6);

        vm.prank(bob);
        uint256 withdrawn = poolManager.withdraw(address(usdc), 10_000e6);
        assertEq(withdrawn, 10_000e6);
    }

    function test_interestAccrual_increasesLiquidityIndex() public {
        vm.startPrank(alice);
        usdc.approve(address(poolManager), 100_000e6);
        poolManager.supply(address(usdc), 100_000e6);
        vm.stopPrank();

        // Drive utilization by borrowing through LendingManager.
        vm.startPrank(bob);
        weth.approve(address(lendingManager), 100e18);
        lendingManager.depositCollateral(address(weth), 100e18);
        lendingManager.borrow(address(usdc), 80_000e6);
        vm.stopPrank();

        uint256 indexBefore = poolManager.getPool(address(usdc)).liquidityIndexRay;

        vm.warp(block.timestamp + 365 days);
        poolManager.accrueInterest(address(usdc));

        uint256 indexAfter = poolManager.getPool(address(usdc)).liquidityIndexRay;
        assertGt(indexAfter, indexBefore, "liquidity index must grow with positive utilization");
    }

    function test_supplyCap_enforced() public {
        address capped = address(new MockERC20("Capped", "CAP", 18));
        vm.startPrank(admin);
        MockERC20(capped).mint(alice, 1_000e18);
        poolManager.createPool(capped, address(rateModel), 1000, 500e18, address(0));
        vm.stopPrank();

        vm.startPrank(alice);
        MockERC20(capped).approve(address(poolManager), 1_000e18);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.AmountExceedsBalance.selector, 600e18, 500e18)
        );
        poolManager.supply(capped, 600e18);
        vm.stopPrank();
    }

    function test_pausedPool_blocksSupply() public {
        vm.prank(admin);
        poolManager.setPoolState(address(usdc), true, false, true);

        vm.startPrank(alice);
        usdc.approve(address(poolManager), 1_000e6);
        vm.expectRevert();
        poolManager.supply(address(usdc), 1_000e6);
        vm.stopPrank();
    }
}
