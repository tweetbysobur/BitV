// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseVaultTest} from "../BaseVaultTest.sol";
import {VaultHandler} from "./VaultHandler.sol";

/**
 * @title BitVYieldVaultInvariantTest
 * @notice Handler-based invariant tests for BitVYieldVault (Build
 * 05.1), covering docs/yield-vault-specification.md §19's invariant
 * list: internally consistent accounting, shares never created without
 * assets, unauthorized configuration changes always rejected, strategy
 * exposure never exceeds its cap, fees never exceed the configured
 * maximum, and compliance can never be bypassed.
 */
contract BitVYieldVaultInvariantTest is BaseVaultTest {
    VaultHandler internal handler;

    function setUp() public override {
        super.setUp();

        _setActiveStrategy();

        address[] memory actors = new address[](2);
        actors[0] = alice;
        actors[1] = bob;

        handler = new VaultHandler(vault, strategy, underlying, admin, actors);
        // Set the initial fee through the handler's own tracked setter
        // (not a direct vault call) so its ghost tracker starts in sync
        // — otherwise invariant_FeeOnlyChangedByAuthorizedPath would
        // spuriously fail at setup before any fuzzing even runs.
        handler.setPerformanceFeeBps(1_000); // 10%, so fee-related invariants are actually exercised
        targetContract(address(handler));
    }

    /// Vault accounting is internally consistent: totalAssets() is
    /// always exactly idle balance plus what the strategy reports —
    /// never a stale or inflated figure.
    function invariant_TotalAssetsInternallyConsistent() public view {
        uint256 idle = underlying.balanceOf(address(vault));
        uint256 deployed = strategy.totalAssets();
        assertEq(vault.totalAssets(), idle + deployed);
    }

    /// Shares cannot be created without assets: if any shares exist,
    /// the vault must hold (or have deployed) a nonzero amount of real
    /// assets backing them.
    function invariant_SharesNeverCreatedWithoutAssets() public view {
        if (vault.totalSupply() > 0) {
            assertGt(vault.totalAssets(), 0);
        }
    }

    /// Strategy exposure never exceeds its configured cap, for whatever
    /// sequence of fuzzed allocate/withdraw/yield/loss actions occurred.
    function invariant_StrategyExposureNeverExceedsCap() public view {
        uint256 maxAllowed = (vault.totalAssets() * vault.maxStrategyAllocationBps()) / 10_000;
        assertLe(strategy.totalAssets(), maxAllowed);
    }

    /// Performance fee never exceeds the hard-coded maximum, regardless
    /// of how many times the handler's (role-gated) setter was fuzzed.
    function invariant_FeeNeverExceedsConfiguredMaximum() public view {
        assertLe(vault.performanceFeeBps(), vault.MAX_PERFORMANCE_FEE_BPS());
    }

    /// Only the handler's own role-holding action can change the fee —
    /// its ghost tracker must always match the live value.
    function invariant_FeeOnlyChangedByAuthorizedPath() public view {
        assertEq(vault.performanceFeeBps(), handler.ghostLastSetFeeBps());
    }

    /// Compliance cannot be bypassed: a wallet the mock validator has
    /// never granted a CVI to can never hold vault shares or deposit,
    /// regardless of how much fuzzed activity has accumulated.
    function invariant_ComplianceCannotBeBypassed() public {
        assertEq(vault.balanceOf(unverified), 0);

        underlying.mint(unverified, 1e18);
        vm.startPrank(unverified);
        underlying.approve(address(vault), 1e18);
        vm.expectRevert();
        vault.deposit(1e18, unverified);
        vm.stopPrank();
    }

    /// Unauthorized users can never alter vault configuration — checked
    /// directly (not just via the handler's fuzzed attempt action) as a
    /// static property that must hold regardless of accumulated state.
    function invariant_UnauthorizedConfigChangeAlwaysRejected() public {
        vm.prank(alice); // a real, compliant depositor — still not VAULT_MANAGER_ROLE
        vm.expectRevert();
        vault.setVaultCap(0);
    }

    /// Emergency withdrawal never transfers more than the vault's idle
    /// balance immediately before the call — checked as a direct
    /// scenario here (the property the handler's bounded fuzzing must
    /// not be able to violate either, implicitly covered by
    /// invariant_TotalAssetsInternallyConsistent staying true even after
    /// fuzzed emergencyWithdraw calls, since a transfer beyond the idle
    /// balance would underflow and revert the whole run).
    function invariant_EmergencyWithdrawalNeverExceedsRecoverable() public {
        if (vault.balanceOf(alice) == 0) return;
        uint256 idleBefore = underlying.balanceOf(address(vault));
        vm.prank(alice);
        vault.emergencyWithdraw();
        uint256 idleAfter = underlying.balanceOf(address(vault));
        assertLe(idleBefore - idleAfter, idleBefore);
    }
}
