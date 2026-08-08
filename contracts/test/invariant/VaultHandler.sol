// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StdUtils} from "forge-std/StdUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {BitVYieldVault} from "../../src/core/BitVYieldVault.sol";
import {TestYieldStrategy} from "../../src/vault/TestYieldStrategy.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Bounded-random-action handler for BitVYieldVault's invariant
/// tests. Mirrors Handler.sol's pattern for the pool/lending suite: every
/// action is wrapped so a revert is swallowed (a fuzz run explores
/// attempted, not guaranteed-successful, action sequences), and only
/// pre-approved compliant actors are used for deposit/withdraw so the
/// fuzzer explores real accounting states rather than mostly hitting the
/// compliance revert path.
contract VaultHandler is StdUtils {
    Vm private constant VM = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    BitVYieldVault public vault;
    TestYieldStrategy public strategy;
    MockERC20 public underlying;
    address public admin;

    address[] public actors;

    /// @notice Ghost tracker: last fee bps this handler itself set via
    /// its own (role-holding) admin action, so the invariant suite can
    /// assert nothing else mutated it.
    uint256 public ghostLastSetFeeBps;

    constructor(
        BitVYieldVault vault_,
        TestYieldStrategy strategy_,
        MockERC20 underlying_,
        address admin_,
        address[] memory actors_
    ) {
        vault = vault_;
        strategy = strategy_;
        underlying = underlying_;
        admin = admin_;
        actors = actors_;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function deposit(uint256 actorSeed, uint96 amount) external {
        address actor = _actor(actorSeed);
        uint256 boundedAmount = bound(amount, 1e6, 1_000_000e18);

        VM.startPrank(actor);
        underlying.mint(actor, boundedAmount);
        underlying.approve(address(vault), boundedAmount);
        try vault.deposit(boundedAmount, actor) {} catch {}
        VM.stopPrank();
    }

    function withdraw(uint256 actorSeed, uint96 amount) external {
        address actor = _actor(actorSeed);
        uint256 maxAssets = vault.maxWithdraw(actor);
        if (maxAssets == 0) return;
        uint256 boundedAmount = bound(amount, 1, maxAssets);

        VM.startPrank(actor);
        try vault.withdraw(boundedAmount, actor, actor) {} catch {}
        VM.stopPrank();
    }

    function redeem(uint256 actorSeed, uint96 shares) external {
        address actor = _actor(actorSeed);
        uint256 balance = vault.balanceOf(actor);
        if (balance == 0) return;
        uint256 boundedShares = bound(shares, 1, balance);

        VM.startPrank(actor);
        try vault.redeem(boundedShares, actor, actor) {} catch {}
        VM.stopPrank();
    }

    function emergencyWithdraw(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        if (vault.balanceOf(actor) == 0) return;

        VM.prank(actor);
        try vault.emergencyWithdraw() {} catch {}
    }

    function allocateToStrategy(uint96 amount) external {
        VM.startPrank(admin);
        try vault.allocateToStrategy(bound(amount, 1, 1_000_000e18)) {} catch {}
        VM.stopPrank();
    }

    function withdrawFromStrategy(uint96 amount) external {
        VM.startPrank(admin);
        try vault.withdrawFromStrategy(bound(amount, 1, 1_000_000e18)) {} catch {}
        VM.stopPrank();
    }

    function simulateYield(uint96 amount) external {
        uint256 boundedAmount = bound(amount, 0, 10_000e18);
        if (boundedAmount == 0) return;
        underlying.mint(address(this), boundedAmount);
        underlying.approve(address(strategy), boundedAmount);
        try strategy.simulateYield(boundedAmount) {} catch {}
    }

    function collectPerformanceFee() external {
        VM.prank(admin);
        try vault.collectPerformanceFee() {} catch {}
    }

    /// @notice The handler's only path that legitimately changes the fee
    /// rate — the invariant suite checks nothing else can.
    function setPerformanceFeeBps(uint256 bps) external {
        uint256 bounded = bound(bps, 0, vault.MAX_PERFORMANCE_FEE_BPS());
        VM.prank(admin);
        vault.setPerformanceFeeBps(bounded);
        ghostLastSetFeeBps = bounded;
    }

    /// @notice Fuzzed attempt at an unauthorized strategy change, from a
    /// non-role-holding actor — must always revert, never succeed.
    function attemptUnauthorizedStrategyChange(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        VM.prank(actor);
        try vault.setStrategy(address(0)) {
            revert("unauthorized setStrategy unexpectedly succeeded");
        } catch {}
    }
}
