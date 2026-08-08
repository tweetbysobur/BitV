// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseVaultTest} from "../BaseVaultTest.sol";
import {BitVYieldVault} from "../../src/core/BitVYieldVault.sol";
import {TestYieldStrategy} from "../../src/vault/TestYieldStrategy.sol";
import {VaultErrors} from "../../src/libraries/VaultErrors.sol";
import {ComplianceErrors} from "../../src/libraries/ComplianceErrors.sol";
import {ProtocolErrors} from "../../src/libraries/ProtocolErrors.sol";
import {IAPassComplianceValidator} from "../../src/interfaces/external/IAPassComplianceValidator.sol";
import {MockReentrantVaultERC20} from "../mocks/MockReentrantVaultERC20.sol";
import {BitVTreasury} from "../../src/core/BitVTreasury.sol";

contract BitVYieldVaultTest is BaseVaultTest {
    // ══════════════════════ CONSTRUCTOR SAFETY (Build 10) ═══════════════

    /// @notice Regression test for Build 10 Phase 1: a zero-address
    /// underlying asset must revert the deployment, not silently create
    /// an unusable vault.
    function test_Constructor_ZeroAsset_Reverts() public {
        vm.expectRevert(VaultErrors.ZeroAddress.selector);
        new BitVYieldVault(
            IERC20(address(0)),
            "BitV Yield Vault Share",
            "bvyVLT",
            address(validator),
            complianceOwner,
            address(accessManager),
            address(treasury),
            0,
            0
        );
    }

    // ══════════════════════════ ACCESS ══════════════════════════════

    function test_VerifiedUser_CanDeposit() public {
        uint256 shares = _depositAs(alice, 1_000e18);
        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
    }

    function test_UnverifiedUser_DepositReverts() public {
        vm.startPrank(unverified);
        underlying.approve(address(vault), 1_000e18);
        vm.expectRevert(
            abi.encodeWithSelector(ComplianceErrors.ComplianceCheckFailed.selector, address(vault), unverified)
        );
        vault.deposit(1_000e18, unverified);
        vm.stopPrank();
    }

    function test_VerifiedUser_CanWithdraw() public {
        _depositAs(alice, 1_000e18);
        vm.prank(alice);
        vault.withdraw(400e18, alice, alice);
        assertEq(underlying.balanceOf(alice), 10_000_000e18 - 1_000e18 + 400e18);
    }

    function test_UnverifiedUser_WithdrawReverts() public {
        _depositAs(alice, 1_000e18);
        // Compliance revoked after deposit (rules cleared for the vault).
        IAPassComplianceValidator.RuleV2[] memory none = new IAPassComplianceValidator.RuleV2[](0);
        validator.setRules(address(vault), none);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ComplianceErrors.ComplianceCheckFailed.selector, address(vault), alice));
        vault.withdraw(100e18, alice, alice);
    }

    function test_UnauthorizedStrategyChange_Reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setStrategy(address(strategy));
    }

    function test_UnauthorizedFeeChange_Reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setPerformanceFeeBps(500);
    }

    function test_UnauthorizedCapChange_Reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setVaultCap(1);
    }

    function test_UnauthorizedPause_Reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setDepositsPaused(true);
    }

    // ══════════════════════════ ACCOUNTING ══════════════════════════

    function test_FirstDeposit_MintsShares() public {
        uint256 shares = _depositAs(alice, 1_000e18);
        assertGt(shares, 0);
        assertEq(vault.totalAssets(), 1_000e18);
    }

    function test_MultipleDeposits_AccumulateShares() public {
        uint256 s1 = _depositAs(alice, 1_000e18);
        uint256 s2 = _depositAs(alice, 500e18);
        assertEq(vault.balanceOf(alice), s1 + s2);
    }

    function test_MultipleUsers_ProRataShares() public {
        uint256 aliceShares = _depositAs(alice, 1_000e18);
        uint256 bobShares = _depositAs(bob, 2_000e18);
        // Bob deposited exactly 2x, with no yield in between -> ~2x shares.
        assertApproxEqRel(bobShares, aliceShares * 2, 0.001e18);
    }

    function test_Withdraw_ReturnsAssets() public {
        _depositAs(alice, 1_000e18);
        uint256 balBefore = underlying.balanceOf(alice);
        vm.prank(alice);
        uint256 sharesBurned = vault.withdraw(300e18, alice, alice);
        assertGt(sharesBurned, 0);
        assertEq(underlying.balanceOf(alice), balBefore + 300e18);
    }

    function test_Redeem_BurnsShares() public {
        uint256 shares = _depositAs(alice, 1_000e18);
        vm.prank(alice);
        uint256 assetsOut = vault.redeem(shares, alice, alice);
        assertEq(vault.balanceOf(alice), 0);
        assertGt(assetsOut, 0);
    }

    function test_SharePrice_ReflectsGrowth() public {
        _setActiveStrategy();
        _depositAs(alice, 1_000e18);
        vm.prank(admin);
        vault.allocateToStrategy(1_000e18);

        uint256 priceBefore = vault.convertToAssets(1e18);

        underlying.mint(address(this), 100e18);
        underlying.approve(address(strategy), 100e18);
        strategy.simulateYield(100e18);

        uint256 priceAfter = vault.convertToAssets(1e18);
        assertGt(priceAfter, priceBefore);
    }

    function test_YieldIncrease_IncreasesShareValueForAllHolders() public {
        _setActiveStrategy();
        uint256 aliceShares = _depositAs(alice, 1_000e18);
        uint256 bobShares = _depositAs(bob, 1_000e18);

        underlying.mint(address(this), 200e18);
        underlying.approve(address(vault), 200e18);
        underlying.transfer(address(vault), 200e18); // idle yield, no strategy needed

        uint256 aliceValue = vault.convertToAssets(aliceShares);
        uint256 bobValue = vault.convertToAssets(bobShares);
        assertGt(aliceValue, 1_000e18);
        assertGt(bobValue, 1_000e18);
    }

    function test_ZeroDeposit_Reverts() public {
        vm.startPrank(alice);
        underlying.approve(address(vault), 0);
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.BelowMinimumDeposit.selector, 0, MIN_DEPOSIT));
        vault.deposit(0, alice);
        vm.stopPrank();
    }

    function test_ZeroShareDeposit_Reverts() public {
        vm.startPrank(alice);
        vm.expectRevert(VaultErrors.ZeroShares.selector);
        vault.mint(0, alice);
        vm.stopPrank();
    }

    // ══════════════════════════ SECURITY ══════════════════════════

    function test_Reentrancy_MaliciousTokenCannotReenterDeposit() public {
        MockReentrantVaultERC20 evilToken = new MockReentrantVaultERC20();
        BitVYieldVault evilVault = new BitVYieldVault(
            evilToken,
            "Evil Vault Share",
            "evVLT",
            address(validator),
            complianceOwner,
            address(accessManager),
            address(treasury),
            VAULT_CAP,
            1
        );
        _grantCompliantCviFor(address(evilVault), alice);

        evilToken.mint(alice, 1_000e18);
        evilToken.configureAttack(address(evilVault), true);

        vm.startPrank(alice);
        evilToken.approve(address(evilVault), 1_000e18);
        // The reentrant call happens inside transferFrom, before the
        // outer deposit's nonReentrant lock is released -> must revert.
        vm.expectRevert();
        evilVault.deposit(1_000e18, alice);
        vm.stopPrank();
    }

    function test_InflationAttack_FirstDepositorCannotStealFromSecond() public {
        // Attacker deposits the minimum, then donates directly to the
        // vault to try to skew the price before the victim deposits.
        _depositAs(alice, MIN_DEPOSIT);
        vm.startPrank(alice);
        underlying.transfer(address(vault), 1_000_000e18); // direct donation, bypassing deposit()
        vm.stopPrank();

        uint256 bobSharesBefore = vault.balanceOf(bob);
        uint256 bobAssetsIn = 1_000e18;
        vm.startPrank(bob);
        underlying.approve(address(vault), bobAssetsIn);
        uint256 bobShares = vault.deposit(bobAssetsIn, bob);
        vm.stopPrank();

        // Bob must receive a fair, nonzero amount of shares — the
        // decimal offset means the donation cannot round Bob down to 0.
        assertGt(bobShares, bobSharesBefore);
        uint256 bobRedeemable = vault.convertToAssets(vault.balanceOf(bob));
        // Bob should be able to redeem a substantial fraction of what
        // he put in (loses at most a small amount to the pre-existing
        // donation's dilution, never gets wiped out to ~0).
        assertGt(bobRedeemable, bobAssetsIn / 2);
    }

    function test_DonationAttack_CannotStealFromExistingDepositors() public {
        _depositAs(alice, 100_000e18);

        uint256 aliceValueBefore = vault.convertToAssets(vault.balanceOf(alice));

        // Attacker donates directly, then deposits and immediately
        // redeems, trying to extract value from Alice's position.
        underlying.mint(bob, 50_000e18);
        vm.startPrank(bob);
        underlying.transfer(address(vault), 10_000e18); // donation
        underlying.approve(address(vault), 40_000e18);
        uint256 bobShares = vault.deposit(40_000e18, bob);
        uint256 bobAssetsOut = vault.redeem(bobShares, bob, bob);
        vm.stopPrank();

        // Bob cannot profit from his own donation (he paid for it and
        // gets back at most what he deposited via deposit(), not the
        // donated amount too).
        assertLe(bobAssetsOut, 40_000e18 + 1); // +1 wei rounding tolerance

        uint256 aliceValueAfter = vault.convertToAssets(vault.balanceOf(alice));
        assertGe(aliceValueAfter, aliceValueBefore); // Alice never loses value
    }

    function test_Rounding_NeverFavorsDepositor() public {
        _depositAs(alice, 999e18 + 7); // odd amount to exercise rounding
        uint256 shares = vault.balanceOf(alice);
        uint256 redeemable = vault.convertToAssets(shares);
        // Redeemable value must never exceed what was deposited (rounding
        // must favor the vault/protocol, not the depositor).
        assertLe(redeemable, 999e18 + 7);
    }

    function test_StrategyInsolvency_SharePriceReflectsLossHonestly() public {
        _setActiveStrategy();
        uint256 shares = _depositAs(alice, 1_000e18);
        vm.prank(admin);
        vault.allocateToStrategy(1_000e18);

        uint256 valueBefore = vault.convertToAssets(shares);

        // Simulate a strategy loss (e.g. hack/failed investment).
        strategy.simulateLoss(400e18, address(0xdead));

        uint256 valueAfter = vault.convertToAssets(shares);
        assertLt(valueAfter, valueBefore);
        assertApproxEqAbs(valueAfter, valueBefore - 400e18, 2);
    }

    function test_UnauthorizedStrategyOperations_Reverts() public {
        _setActiveStrategy();
        vm.prank(alice);
        vm.expectRevert();
        vault.allocateToStrategy(1e18);

        vm.prank(alice);
        vm.expectRevert();
        vault.withdrawFromStrategy(1e18);

        vm.prank(alice);
        vm.expectRevert();
        vault.emergencyExitStrategy();
    }

    function test_FeeManipulation_CannotExceedCap() public {
        // vault.MAX_PERFORMANCE_FEE_BPS() is itself an external call —
        // computed *before* vm.prank so it doesn't consume the single
        // next-call prank (the same class of bug documented elsewhere
        // in this codebase's test history).
        uint256 tooHigh = vault.MAX_PERFORMANCE_FEE_BPS() + 1;
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.InvalidBps.selector, tooHigh));
        vault.setPerformanceFeeBps(tooHigh);
    }

    function test_VaultCapBypass_Reverts() public {
        vm.prank(admin);
        vault.setVaultCap(500e18);

        vm.startPrank(alice);
        underlying.approve(address(vault), 1_000e18);
        vm.expectRevert();
        vault.deposit(1_000e18, alice);
        vm.stopPrank();
    }

    function test_StrategyCapBypass_Reverts() public {
        vm.startPrank(admin);
        vault.setStrategy(address(strategy));
        vault.setMaxStrategyAllocationBps(1_000); // 10%
        vault.setMinIdleReserveBps(0);
        vm.stopPrank();

        _depositAs(alice, 1_000e18);

        vm.prank(admin);
        vm.expectRevert(); // 200e18 > 10% of 1_000e18
        vault.allocateToStrategy(200e18);
    }

    // ══════════════════════════ STRATEGY ══════════════════════════

    function test_Strategy_AllocationSucceeds() public {
        _setActiveStrategy();
        _depositAs(alice, 1_000e18);

        vm.prank(admin);
        vault.allocateToStrategy(600e18);

        assertEq(strategy.totalAssets(), 600e18);
        assertEq(vault.totalAssets(), 1_000e18);
    }

    function test_Strategy_WithdrawalReturnsFunds() public {
        _setActiveStrategy();
        _depositAs(alice, 1_000e18);
        vm.startPrank(admin);
        vault.allocateToStrategy(600e18);
        vault.withdrawFromStrategy(400e18);
        vm.stopPrank();

        assertEq(strategy.totalAssets(), 200e18);
        assertEq(underlying.balanceOf(address(vault)), 800e18);
    }

    function test_Strategy_ReplacementExitsOldStrategy() public {
        _setActiveStrategy();
        _depositAs(alice, 1_000e18);
        vm.prank(admin);
        vault.allocateToStrategy(600e18);

        TestYieldStrategy newStrategy = new TestYieldStrategy(address(underlying), address(vault), true);
        vm.prank(admin);
        vault.setStrategy(address(newStrategy));

        assertEq(strategy.totalAssets(), 0); // fully exited
        assertEq(vault.totalAssets(), 1_000e18); // nothing lost
    }

    function test_Strategy_AllocationCapEnforced() public {
        _setActiveStrategy();
        vm.prank(admin);
        vault.setMaxStrategyAllocationBps(5_000); // 50%
        _depositAs(alice, 1_000e18);

        vm.prank(admin);
        vm.expectRevert();
        vault.allocateToStrategy(600e18); // > 50% of 1,000e18
    }

    function test_Strategy_EmergencyExitRecoversFunds() public {
        _setActiveStrategy();
        _depositAs(alice, 1_000e18);
        vm.prank(admin);
        vault.allocateToStrategy(600e18);

        vm.prank(admin);
        vault.emergencyExitStrategy();

        assertEq(strategy.totalAssets(), 0);
        assertEq(underlying.balanceOf(address(vault)), 1_000e18);
    }

    function test_Strategy_Failure() public {
        _setActiveStrategy();
        _depositAs(alice, 1_000e18);
        vm.prank(admin);
        vault.allocateToStrategy(1_000e18);

        strategy.simulateLoss(1_000e18, address(0xdead)); // total loss

        assertEq(vault.totalAssets(), 0);
        // The vault must not revert just reporting this — it does so
        // honestly, as asserted above.
    }

    // ══════════════════════════ FEES ══════════════════════════

    function test_PerformanceFee_AccruesOnYield() public {
        vm.prank(admin);
        vault.setPerformanceFeeBps(1_000); // 10%

        _depositAs(alice, 1_000e18);
        _depositAs(bob, 1_000e18); // triggers an accrual check; no profit yet, no fee

        assertEq(vault.balanceOf(address(vault)), 0);

        underlying.mint(address(this), 1_000e18);
        underlying.approve(address(vault), 1_000e18);
        underlying.transfer(address(vault), 1_000e18); // 1,000e18 profit, idle

        vm.prank(admin);
        uint256 collected = vault.collectPerformanceFee();

        // 10% of 1,000e18 profit = 100e18, modulo rounding.
        assertApproxEqAbs(collected, 100e18, 1e15);
    }

    function test_PerformanceFee_CannotExceedCap() public {
        vm.prank(admin);
        vm.expectRevert();
        vault.setPerformanceFeeBps(2_001);
    }

    function test_PerformanceFee_RecipientIsTreasury() public {
        vm.prank(admin);
        vault.setPerformanceFeeBps(1_000);
        _depositAs(alice, 1_000e18);

        underlying.mint(address(this), 500e18);
        underlying.approve(address(vault), 500e18);
        underlying.transfer(address(vault), 500e18);

        uint256 treasuryBalBefore = underlying.balanceOf(address(treasury));
        vm.prank(admin);
        uint256 collected = vault.collectPerformanceFee();

        assertEq(underlying.balanceOf(address(treasury)), treasuryBalBefore + collected);
    }

    function test_TreasuryAccounting_EventEmitted() public {
        vm.prank(admin);
        vault.setPerformanceFeeBps(1_000);
        _depositAs(alice, 1_000e18);
        underlying.mint(address(this), 500e18);
        underlying.approve(address(vault), 500e18);
        underlying.transfer(address(vault), 500e18);

        // Assert the treasury emits FeeReceived from the right asset and
        // sender (checkData left false since the exact wei amount is
        // subject to ERC-4626 share-rounding, verified separately below
        // via the balance delta instead of an exact event-data match).
        uint256 expectedFeeAssets = (500e18 * 1_000) / 10_000;
        vm.expectEmit(true, true, false, false, address(treasury));
        emit BitVTreasury.FeeReceived(address(underlying), address(vault), expectedFeeAssets);

        vm.prank(admin);
        uint256 collected = vault.collectPerformanceFee();
        assertApproxEqAbs(collected, expectedFeeAssets, 1e12); // small share-rounding tolerance
    }

    function test_UnauthorizedFeeUpdate_Reverts() public {
        vm.prank(bob);
        vm.expectRevert();
        vault.setPerformanceFeeBps(100);
    }

    // ══════════════════════════ PAUSE ══════════════════════════

    function test_DepositPause_BlocksDeposit() public {
        vm.prank(admin);
        vault.setDepositsPaused(true);

        vm.startPrank(alice);
        underlying.approve(address(vault), 1_000e18);
        vm.expectRevert(VaultErrors.DepositsPaused.selector);
        vault.deposit(1_000e18, alice);
        vm.stopPrank();
    }

    function test_WithdrawalPause_BlocksNormalWithdrawal() public {
        _depositAs(alice, 1_000e18);
        vm.prank(admin);
        vault.setWithdrawalsPaused(true);

        vm.prank(alice);
        vm.expectRevert(VaultErrors.WithdrawalsPaused.selector);
        vault.withdraw(100e18, alice, alice);
    }

    function test_StrategyPause_BlocksAllocation() public {
        _setActiveStrategy();
        _depositAs(alice, 1_000e18);
        vm.prank(admin);
        vault.setStrategyPaused(true);

        vm.prank(admin);
        vm.expectRevert(VaultErrors.StrategyOperationsPaused.selector);
        vault.allocateToStrategy(100e18);
    }

    function test_EmergencyWithdrawal_AvailableDuringWithdrawalPause() public {
        _depositAs(alice, 1_000e18);
        vm.prank(admin);
        vault.setWithdrawalsPaused(true);

        vm.prank(alice);
        uint256 returned = vault.emergencyWithdraw();
        assertEq(returned, 1_000e18);
        assertEq(vault.balanceOf(alice), 0);
    }

    // ══════════════════════════ COMPLIANCE ══════════════════════════

    function test_ComplianceRequired_BeforeDeposit() public {
        vm.startPrank(unverified);
        underlying.approve(address(vault), 1e18);
        vm.expectRevert();
        vault.deposit(1e18, unverified);
        vm.stopPrank();
    }

    function test_ComplianceRequired_BeforeWithdrawal() public {
        _depositAs(alice, 1_000e18);
        IAPassComplianceValidator.RuleV2[] memory none = new IAPassComplianceValidator.RuleV2[](0);
        validator.setRules(address(vault), none);

        // balanceOf is itself an external (staticcall) call — read it
        // *before* vm.prank so it doesn't consume the single next-call
        // prank ahead of the actual redeem() call under test.
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(aliceShares, alice, alice);
    }

    function test_NoShareTransferComplianceBypass() public {
        _depositAs(alice, 1_000e18);
        vm.prank(alice);
        vm.expectRevert(VaultErrors.OnlySelfService.selector);
        vault.transfer(unverified, 1e18);

        vm.prank(alice);
        vault.approve(unverified, 1e18);
        vm.prank(unverified);
        vm.expectRevert(VaultErrors.OnlySelfService.selector);
        vault.transferFrom(alice, unverified, 1e18);
    }

    // ── Helper: grant compliance for a custom vault instance ──────────
    function _grantCompliantCviFor(address vaultAddress, address user) internal {
        validator.setUser(user, GROUP_RETAIL, SUBGROUP_STANDARD, TIER_1, 0, 0);
        IAPassComplianceValidator.RuleV2[] memory rules = new IAPassComplianceValidator.RuleV2[](1);
        rules[0] = _permissiveRule();
        validator.setRules(vaultAddress, rules);
    }
}
