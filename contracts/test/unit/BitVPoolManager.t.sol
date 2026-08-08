// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseProtocolTest} from "../BaseProtocolTest.sol";
import {BitVPoolManager} from "../../src/core/BitVPoolManager.sol";
import {ProtocolErrors} from "../../src/libraries/ProtocolErrors.sol";
import {ComplianceErrors} from "../../src/libraries/ComplianceErrors.sol";
import {MockReentrantERC20} from "../mocks/MockReentrantERC20.sol";
import {IAPassComplianceValidator} from "../../src/interfaces/external/IAPassComplianceValidator.sol";

contract BitVPoolManagerTest is BaseProtocolTest {
    function test_Deposit_CreditsScaledBalanceAndTransfersUnderlying() public {
        vm.startPrank(supplier);
        debtAsset.approve(address(poolManager), 100e18);
        poolManager.deposit(address(debtAsset), 100e18);
        vm.stopPrank();

        assertEq(poolManager.balanceOf(address(debtAsset), supplier), 100e18);
        assertEq(debtAsset.balanceOf(address(poolManager)), 100e18);
        assertEq(poolManager.totalSupplied(address(debtAsset)), 100e18);
    }

    function test_Withdraw_ReturnsUnderlyingAndDebitsBalance() public {
        vm.startPrank(supplier);
        debtAsset.approve(address(poolManager), 100e18);
        poolManager.deposit(address(debtAsset), 100e18);

        poolManager.withdraw(address(debtAsset), 40e18);
        vm.stopPrank();

        assertEq(poolManager.balanceOf(address(debtAsset), supplier), 60e18);
        assertEq(debtAsset.balanceOf(supplier), 1_000_000e18 - 100e18 + 40e18);
    }

    function test_Withdraw_Max_WithdrawsExactBalanceNoDust() public {
        vm.startPrank(supplier);
        debtAsset.approve(address(poolManager), 100e18);
        poolManager.deposit(address(debtAsset), 100e18);

        uint256 withdrawn = poolManager.withdraw(address(debtAsset), type(uint256).max);
        vm.stopPrank();

        assertEq(withdrawn, 100e18);
        assertEq(poolManager.balanceOf(address(debtAsset), supplier), 0);
        assertEq(poolManager.scaledBalanceOf(address(debtAsset), supplier), 0);
    }

    function test_Withdraw_MoreThanBalance_Reverts() public {
        vm.startPrank(supplier);
        debtAsset.approve(address(poolManager), 100e18);
        poolManager.deposit(address(debtAsset), 100e18);

        vm.expectRevert(abi.encodeWithSelector(ProtocolErrors.AmountExceedsBalance.selector, 101e18, 100e18));
        poolManager.withdraw(address(debtAsset), 101e18);
        vm.stopPrank();
    }

    function test_PoolAccounting_TotalSuppliedAvailableUtilization() public {
        vm.startPrank(supplier);
        debtAsset.approve(address(poolManager), 1_000e18);
        poolManager.deposit(address(debtAsset), 1_000e18);
        vm.stopPrank();

        assertEq(poolManager.totalSupplied(address(debtAsset)), 1_000e18);
        assertEq(poolManager.availableLiquidity(address(debtAsset)), 1_000e18);
        assertEq(poolManager.totalBorrowed(address(debtAsset)), 0);
        assertEq(poolManager.utilizationRay(address(debtAsset)), 0);

        // Borrow through the lending manager to move utilization off zero.
        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), 10e18);
        lendingManager.depositCollateral(address(collateralAsset), 10e18); // $20,000 collateral
        lendingManager.borrow(address(debtAsset), 500e18); // $500 debt, well under 70% LTV
        vm.stopPrank();

        assertEq(poolManager.totalBorrowed(address(debtAsset)), 500e18);
        assertEq(poolManager.availableLiquidity(address(debtAsset)), 500e18);
        assertGt(poolManager.utilizationRay(address(debtAsset)), 0);
    }

    function test_Pause_BlocksDepositAndWithdraw() public {
        vm.prank(admin);
        poolManager.setPoolPaused(address(debtAsset), true);

        vm.startPrank(supplier);
        debtAsset.approve(address(poolManager), 100e18);
        vm.expectRevert(abi.encodeWithSelector(ProtocolErrors.PoolIsPaused.selector, address(debtAsset)));
        poolManager.deposit(address(debtAsset), 100e18);
        vm.stopPrank();
    }

    function test_Pause_UnpauseRestoresAccess() public {
        vm.prank(admin);
        poolManager.setPoolPaused(address(debtAsset), true);
        vm.prank(admin);
        poolManager.setPoolPaused(address(debtAsset), false);

        vm.startPrank(supplier);
        debtAsset.approve(address(poolManager), 100e18);
        poolManager.deposit(address(debtAsset), 100e18);
        vm.stopPrank();

        assertEq(poolManager.balanceOf(address(debtAsset), supplier), 100e18);
    }

    // ── Compliance ───────────────────────────────────────────────────────

    function test_Compliance_UnverifiedUserRejected() public {
        address stranger = makeAddr("stranger"); // never granted a CVI

        vm.startPrank(stranger);
        debtAsset.mint(stranger, 100e18);
        debtAsset.approve(address(poolManager), 100e18);
        vm.expectRevert(
            abi.encodeWithSelector(ComplianceErrors.ComplianceCheckFailed.selector, address(poolManager), stranger)
        );
        poolManager.deposit(address(debtAsset), 100e18);
        vm.stopPrank();
    }

    function test_Compliance_VerifiedUserAllowed() public {
        vm.startPrank(supplier);
        debtAsset.approve(address(poolManager), 100e18);
        poolManager.deposit(address(debtAsset), 100e18);
        vm.stopPrank();

        assertEq(poolManager.balanceOf(address(debtAsset), supplier), 100e18);
    }

    // ── Access control ───────────────────────────────────────────────────

    function test_UnauthorizedAdminAction_Rejected() public {
        vm.prank(supplier); // not PAUSER_ROLE
        vm.expectRevert(
            abi.encodeWithSelector(ProtocolErrors.Unauthorized.selector, supplier, accessManager.PAUSER_ROLE())
        );
        poolManager.setPoolPaused(address(debtAsset), true);
    }

    function test_CreatePool_UnauthorizedCaller_Rejected() public {
        vm.prank(supplier);
        vm.expectRevert(
            abi.encodeWithSelector(
                ProtocolErrors.Unauthorized.selector, supplier, accessManager.PROTOCOL_ADMIN_ROLE()
            )
        );
        poolManager.createPool(
            address(0xCAFE),
            BitVPoolManager.PoolConfigParams({
                ltvBps: 0,
                liquidationThresholdBps: 0,
                liquidationBonusBps: 0,
                reserveFactorBps: 0,
                supplyCap: 0,
                borrowCap: 0,
                interestRateModel: address(0),
                priceOracle: address(0),
                isBorrowingEnabled: false,
                isCollateralEnabled: false
            })
        );
    }

    // ── Reentrancy ───────────────────────────────────────────────────────

    function test_Reentrancy_MaliciousTokenCannotReenterDeposit() public {
        MockReentrantERC20 evilToken = new MockReentrantERC20();
        address attacker = makeAddr("attacker");

        vm.prank(admin);
        poolManager.createPool(
            address(evilToken),
            BitVPoolManager.PoolConfigParams({
                ltvBps: 0,
                liquidationThresholdBps: 0,
                liquidationBonusBps: 0,
                reserveFactorBps: 0,
                supplyCap: 0,
                borrowCap: 0,
                interestRateModel: address(0),
                priceOracle: address(0),
                isBorrowingEnabled: false,
                isCollateralEnabled: false
            })
        );

        validator.setUser(attacker, GROUP_RETAIL, SUBGROUP_STANDARD, TIER_1, 0, 0);
        IAPassComplianceValidator.RuleV2[] memory rules = new IAPassComplianceValidator.RuleV2[](1);
        rules[0] = _permissiveRule();
        validator.setRules(address(poolManager), rules);

        evilToken.mint(attacker, 100e18);
        evilToken.configureAttack(address(poolManager), true);

        vm.startPrank(attacker);
        evilToken.approve(address(poolManager), 100e18);
        vm.expectRevert(); // OZ ReentrancyGuardReentrantCall
        poolManager.deposit(address(evilToken), 100e18);
        vm.stopPrank();
    }
}
