// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseProtocolTest} from "../BaseProtocolTest.sol";
import {BitVPoolManager} from "../../src/core/BitVPoolManager.sol";
import {BitVTreasury} from "../../src/core/BitVTreasury.sol";
import {ProtocolErrors} from "../../src/libraries/ProtocolErrors.sol";
import {MockReentrantOnTransferERC20} from "../mocks/MockReentrantOnTransferERC20.sol";
import {IAPassComplianceValidator} from "../../src/interfaces/external/IAPassComplianceValidator.sol";

/// @notice Covers Prompt 14: BitVTreasury's ability to claim its own
/// accrued pool reserve-factor interest from BitVPoolManager. The pool
/// fixture (see BaseProtocolTest) already configures `debtAsset`'s pool
/// with a 10% reserveFactorBps and `collateralAsset`'s pool with 0%.
contract BitVTreasuryReserveClaimTest is BaseProtocolTest {
    function _supplyLiquidity(uint256 amount) internal {
        vm.startPrank(supplier);
        debtAsset.approve(address(poolManager), amount);
        poolManager.deposit(address(debtAsset), amount);
        vm.stopPrank();
    }

    function _depositCollateral(address user, uint256 amount) internal {
        collateralAsset.mint(user, amount);
        vm.startPrank(user);
        collateralAsset.approve(address(lendingManager), amount);
        lendingManager.depositCollateral(address(collateralAsset), amount);
        vm.stopPrank();
    }

    function _accrueSomeReserve() internal {
        _supplyLiquidity(10_000e18);
        _depositCollateral(borrower, 10e18);

        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 8_000e18); // 80% utilization, at the kink

        vm.warp(block.timestamp + 365 days);
        poolManager.accrueInterest(address(debtAsset));
    }

    // ── Reserve-factor accrual ──────────────────────────────────────────

    function test_ReserveAccrual_CreditsTreasuryScaledSupply() public {
        assertEq(poolManager.reserveBalance(address(debtAsset)), 0);

        _accrueSomeReserve();

        uint256 reserve = poolManager.reserveBalance(address(debtAsset));
        assertGt(reserve, 0);
        assertEq(reserve, poolManager.balanceOf(address(debtAsset), address(treasury)));
    }

    function test_ReserveAccrual_ZeroReserveFactorPool_NeverCreditsTreasury() public {
        // collateralAsset's pool was created with reserveFactorBps: 0.
        collateralAsset.mint(supplier, 100e18);
        vm.startPrank(supplier);
        collateralAsset.approve(address(poolManager), 100e18);
        poolManager.deposit(address(collateralAsset), 100e18);
        vm.stopPrank();

        _depositCollateral(borrower, 5e18);
        vm.warp(block.timestamp + 365 days);
        poolManager.accrueInterest(address(collateralAsset));

        assertEq(poolManager.reserveBalance(address(collateralAsset)), 0);
    }

    // ── Treasury claim ───────────────────────────────────────────────────

    function test_TreasuryClaim_FullAmount_TransfersUnderlyingAndZeroesReserve() public {
        _accrueSomeReserve();
        uint256 reserve = poolManager.reserveBalance(address(debtAsset));
        assertGt(reserve, 0);

        vm.prank(admin);
        uint256 claimed = treasury.claimPoolReserve(address(poolManager), address(debtAsset), type(uint256).max);

        assertEq(claimed, reserve);
        assertEq(debtAsset.balanceOf(address(treasury)), reserve);
        assertEq(poolManager.reserveBalance(address(debtAsset)), 0);
    }

    function test_TreasuryClaim_PartialAmount_LeavesRemainderAccruing() public {
        _accrueSomeReserve();
        uint256 reserve = poolManager.reserveBalance(address(debtAsset));
        uint256 half = reserve / 2;

        vm.prank(admin);
        uint256 claimed = treasury.claimPoolReserve(address(poolManager), address(debtAsset), half);

        assertEq(claimed, half);
        assertEq(debtAsset.balanceOf(address(treasury)), half);
        assertApproxEqAbs(poolManager.reserveBalance(address(debtAsset)), reserve - half, 1);
    }

    function test_TreasuryClaim_Repeated_EachClaimIndependentlyCorrect() public {
        _accrueSomeReserve();

        vm.startPrank(admin);
        uint256 first = treasury.claimPoolReserve(address(poolManager), address(debtAsset), 1e18);
        assertEq(first, 1e18);
        assertEq(debtAsset.balanceOf(address(treasury)), 1e18);

        // More interest accrues between claims.
        vm.warp(block.timestamp + 30 days);
        poolManager.accrueInterest(address(debtAsset));

        uint256 second = treasury.claimPoolReserve(address(poolManager), address(debtAsset), type(uint256).max);
        vm.stopPrank();

        assertGt(second, 0);
        assertEq(debtAsset.balanceOf(address(treasury)), 1e18 + second);
        assertEq(poolManager.reserveBalance(address(debtAsset)), 0);
    }

    function test_TreasuryClaim_Zero_Reverts() public {
        _accrueSomeReserve();

        vm.prank(admin);
        vm.expectRevert(ProtocolErrors.ZeroAmount.selector);
        treasury.claimPoolReserve(address(poolManager), address(debtAsset), 0);
    }

    function test_TreasuryClaim_NoAccruedReserve_MaxAmountReverts() public {
        // No borrowing/accrual has happened yet — reserve is exactly zero.
        vm.prank(admin);
        vm.expectRevert(ProtocolErrors.ZeroAmount.selector);
        treasury.claimPoolReserve(address(poolManager), address(debtAsset), type(uint256).max);
    }

    function test_TreasuryClaim_MultiplePools_IndependentBalances() public {
        // Give collateralAsset's pool a nonzero reserve factor too, purely
        // for this test, without touching the shared debtAsset pool.
        vm.prank(admin);
        poolManager.setReserveFactor(address(collateralAsset), 1_000);

        collateralAsset.mint(supplier, 1_000e18);
        vm.startPrank(supplier);
        collateralAsset.approve(address(poolManager), 1_000e18);
        poolManager.deposit(address(collateralAsset), 1_000e18);
        vm.stopPrank();

        _accrueSomeReserve(); // accrues reserve on debtAsset's pool only

        assertEq(poolManager.reserveBalance(address(collateralAsset)), 0);
        uint256 debtReserve = poolManager.reserveBalance(address(debtAsset));
        assertGt(debtReserve, 0);

        vm.prank(admin);
        treasury.claimPoolReserve(address(poolManager), address(debtAsset), type(uint256).max);

        // Claiming debtAsset's reserve must not touch collateralAsset's pool.
        assertEq(poolManager.reserveBalance(address(collateralAsset)), 0);
        assertEq(collateralAsset.balanceOf(address(treasury)), 0);
        assertEq(poolManager.reserveBalance(address(debtAsset)), 0);
    }

    // ── Access control ───────────────────────────────────────────────────

    function test_TreasuryClaim_UnauthorizedCaller_Reverts() public {
        _accrueSomeReserve();

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        treasury.claimPoolReserve(address(poolManager), address(debtAsset), type(uint256).max);
    }

    function test_PoolManagerClaimReserve_DirectNonTreasuryCaller_Reverts() public {
        _accrueSomeReserve();

        // Even PROTOCOL_ADMIN_ROLE cannot call PoolManager.claimReserve
        // directly — only the treasury contract itself, as msg.sender.
        vm.prank(admin);
        vm.expectRevert(ProtocolErrors.CallerNotTreasury.selector);
        poolManager.claimReserve(address(debtAsset), type(uint256).max);
    }

    // ── Wrong asset / insufficient reserve ──────────────────────────────

    function test_TreasuryClaim_AssetWithNoPool_Reverts() public {
        address randomAsset = makeAddr("randomAsset");
        vm.prank(admin);
        vm.expectRevert(); // PoolNotActive
        treasury.claimPoolReserve(address(poolManager), randomAsset, 1);
    }

    function test_TreasuryClaim_MoreThanAccrued_Reverts() public {
        _accrueSomeReserve();
        uint256 reserve = poolManager.reserveBalance(address(debtAsset));

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(ProtocolErrors.AmountExceedsBalance.selector, reserve + 1, reserve)
        );
        treasury.claimPoolReserve(address(poolManager), address(debtAsset), reserve + 1);
    }

    function test_TreasuryClaim_ZeroToAddress_NotApplicable_TreasuryIsFixed() public {
        // claimPoolReserve always sends to `address(this)` (the treasury) —
        // there is no destination parameter to misuse, unlike withdraw().
        _accrueSomeReserve();
        vm.prank(admin);
        treasury.claimPoolReserve(address(poolManager), address(debtAsset), 1e18);
        assertEq(debtAsset.balanceOf(address(treasury)), 1e18);
    }

    // ── Reentrancy ───────────────────────────────────────────────────────

    function test_Reentrancy_MaliciousTokenCannotReenterClaimReserve() public {
        MockReentrantOnTransferERC20 evilToken = new MockReentrantOnTransferERC20();

        vm.prank(admin);
        poolManager.createPool(
            address(evilToken),
            BitVPoolManager.PoolConfigParams({
                ltvBps: 0,
                maxLtvWithScoreBps: 0,
                liquidationThresholdBps: 0,
                liquidationBonusBps: 0,
                reserveFactorBps: 10_000, // 100% of interest -> reserve, to make this easy to set up
                supplyCap: 0,
                borrowCap: 0,
                interestRateModel: address(rateModel),
                priceOracle: address(oracle),
                isBorrowingEnabled: true,
                isCollateralEnabled: false
            })
        );

        vm.prank(admin);
        oracle.setPrice(address(evilToken), 1e18, 18);

        // `claimReserve`'s guard doesn't care how TREASURY's scaled
        // balance was credited — only that its own execution can't be
        // reentered. Give TREASURY a claimable position the simplest way
        // available in a unit test: prank it through an ordinary deposit
        // (in production this balance is always credited by
        // `accrueInterest`, exercised by the other tests in this file).
        // `deposit()` is still compliance-gated for any caller (including
        // TREASURY, here standing in for "some address"), so register it.
        _grantCompliantCvi(address(treasury));
        evilToken.mint(address(treasury), 50e18);
        vm.startPrank(address(treasury));
        evilToken.approve(address(poolManager), 50e18);
        poolManager.deposit(address(evilToken), 50e18);
        vm.stopPrank();

        evilToken.configureAttack(
            address(poolManager),
            abi.encodeWithSelector(BitVPoolManager.claimReserve.selector, address(evilToken), uint256(1)),
            true
        );

        vm.prank(address(treasury));
        vm.expectRevert(); // OZ ReentrancyGuardReentrantCall
        poolManager.claimReserve(address(evilToken), 1e18);
    }

    // ── Accounting invariants around a claim ────────────────────────────

    function test_TreasuryClaim_DoesNotAffectSupplierBalance() public {
        _accrueSomeReserve();
        uint256 supplierBalanceBefore = poolManager.balanceOf(address(debtAsset), supplier);

        vm.prank(admin);
        treasury.claimPoolReserve(address(poolManager), address(debtAsset), type(uint256).max);

        assertEq(poolManager.balanceOf(address(debtAsset), supplier), supplierBalanceBefore);
    }

    function test_TreasuryClaim_DoesNotAffectBorrowerDebt() public {
        _accrueSomeReserve();
        uint256 debtBefore = lendingManager.getCurrentDebt(borrower, address(debtAsset));

        vm.prank(admin);
        treasury.claimPoolReserve(address(poolManager), address(debtAsset), type(uint256).max);

        assertEq(lendingManager.getCurrentDebt(borrower, address(debtAsset)), debtBefore);
    }

    function test_TreasuryClaim_PoolLiquidityDecreasesByExactlyClaimedAmount() public {
        _accrueSomeReserve();
        uint256 liquidityBefore = poolManager.availableLiquidity(address(debtAsset));
        uint256 reserve = poolManager.reserveBalance(address(debtAsset));

        vm.prank(admin);
        uint256 claimed = treasury.claimPoolReserve(address(poolManager), address(debtAsset), type(uint256).max);

        assertEq(claimed, reserve);
        assertEq(poolManager.availableLiquidity(address(debtAsset)), liquidityBefore - claimed);
    }

    function test_TreasuryClaim_SupplierCanStillWithdrawFullBalanceAfterClaim() public {
        _accrueSomeReserve();

        vm.prank(admin);
        treasury.claimPoolReserve(address(poolManager), address(debtAsset), type(uint256).max);

        uint256 supplierBalance = poolManager.balanceOf(address(debtAsset), supplier);
        vm.prank(borrower);
        // Repay so there's enough liquidity for the supplier's full withdrawal.
        debtAsset.mint(borrower, 20_000e18);
        vm.startPrank(borrower);
        debtAsset.approve(address(lendingManager), type(uint256).max);
        lendingManager.repay(address(debtAsset), type(uint256).max);
        vm.stopPrank();

        vm.prank(supplier);
        uint256 withdrawn = poolManager.withdraw(address(debtAsset), type(uint256).max);
        assertEq(withdrawn, supplierBalance);
    }
}
