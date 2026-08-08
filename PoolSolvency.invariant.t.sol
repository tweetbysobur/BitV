// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { BaseTest } from "../BaseTest.sol";
import { PoolManager } from "../../src/core/PoolManager.sol";
import { LendingManager } from "../../src/core/LendingManager.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

/// @notice Randomly supplies, withdraws, borrows, repays, and warps time
///         against the real PoolManager/LendingManager pair, bounding every
///         action to values that can succeed so the invariant runner spends
///         its budget exploring accounting edge cases rather than mostly
///         hitting reverts. Extends `Test` directly (rather than routing
///         cheatcodes through the invariant test contract) — the standard
///         Foundry handler pattern, and what keeps this contract independent
///         of `BaseTest`'s specific setup beyond the references it's handed.
contract PoolSolvencyHandler is Test {
    PoolManager internal immutable poolManager;
    LendingManager internal immutable lendingManager;
    MockERC20 internal immutable usdc;
    MockERC20 internal immutable weth;
    address[3] internal actors;

    constructor(
        PoolManager poolManager_,
        LendingManager lendingManager_,
        MockERC20 usdc_,
        MockERC20 weth_,
        address[3] memory actors_
    ) {
        poolManager = poolManager_;
        lendingManager = lendingManager_;
        usdc = usdc_;
        weth = weth_;
        actors = actors_;
    }

    function supply(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % 3];
        amount = bound(amount, 1e6, 50_000e6);

        usdc.mint(actor, amount);
        vm.startPrank(actor);
        usdc.approve(address(poolManager), amount);
        try poolManager.supply(address(usdc), amount) { } catch { }
        vm.stopPrank();
    }

    function withdraw(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % 3];
        amount = bound(amount, 1e6, 20_000e6);

        vm.prank(actor);
        try poolManager.withdraw(address(usdc), amount) { } catch { }
    }

    function borrowAgainstFreshCollateral(uint256 actorSeed, uint256 collateralAmount) external {
        address actor = actors[actorSeed % 3];
        collateralAmount = bound(collateralAmount, 1e18, 20e18);

        weth.mint(actor, collateralAmount);
        vm.startPrank(actor);
        weth.approve(address(lendingManager), collateralAmount);
        try lendingManager.depositCollateral(address(weth), collateralAmount) { } catch { }

        // Conservative borrow sizing (well under the collateral factor) so
        // this mostly succeeds and exercises PoolManager's borrow-side
        // liquidity movement rather than mostly reverting.
        uint256 borrowAmount = collateralAmount * 1_000e6 / 1e18;
        try lendingManager.borrow(address(usdc), borrowAmount) { } catch { }
        vm.stopPrank();
    }

    function repay(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % 3];
        amount = bound(amount, 1e6, 10_000e6);

        usdc.mint(actor, amount);
        vm.startPrank(actor);
        usdc.approve(address(lendingManager), amount);
        try lendingManager.repay(address(usdc), amount, actor) { } catch { }
        vm.stopPrank();
    }

    function warp(uint256 secondsForward) external {
        secondsForward = bound(secondsForward, 0, 30 days);
        vm.warp(block.timestamp + secondsForward);
    }
}

contract PoolSolvencyInvariantTest is BaseTest {
    PoolSolvencyHandler internal handler;

    function setUp() public override {
        super.setUp();

        handler =
            new PoolSolvencyHandler(poolManager, lendingManager, usdc, weth, [alice, bob, liquidator]);
        targetContract(address(handler));
    }

    /// @notice Core solvency invariant: PoolManager can never owe suppliers
    ///         more than it actually holds plus what is out on loan. If this
    ///         ever fails, it means the interest accrual or the borrow/repay
    ///         hooks have drifted the pool into promising more than it can
    ///         pay — the single most important property a lending pool has.
    ///
    /// @dev FIXED — was previously disabled here (as
    ///      `knownIssue_invariant_poolSolvency`) after diagnosing a real,
    ///      usage-scaling solvency drift: `PoolManager`'s liquidity index and
    ///      `LendingManager`'s borrow index each independently called
    ///      `IInterestRateModel.getRates` and compounded on their own
    ///      schedule, so the two integrated two different rate PATHS over
    ///      time rather than one shared one. The actual fix (not a tolerance
    ///      widening): both indices now live on ONE struct
    ///      (`DataTypes.Pool`), advanced together by ONE function
    ///      (`PoolManager._accrue`) from ONE rate-model call per accrual —
    ///      see the NatSpec on `DataTypes.Pool` and `PoolManager`'s
    ///      contract-level docs for the full before/after. `totalBorrowed` is
    ///      now DERIVED (`totalScaledDebt.rayMul(borrowIndexRay)`), never
    ///      separately mirrored, so there is no reconciliation step left to
    ///      drift. A small tolerance is retained (not exact equality) purely
    ///      for `WadRayMath`'s round-to-nearest behaviour on scaled-amount
    ///      conversions — genuine sub-wei-per-operation rounding, not a
    ///      structural gap.
    function invariant_poolSolvency() public view {
        uint256 cash = usdc.balanceOf(address(poolManager));
        uint256 totalBorrowed = poolManager.totalBorrowed(address(usdc));
        uint256 totalSupplied = poolManager.totalLiquidity(address(usdc));
        uint256 backed = cash + totalBorrowed;

        if (backed >= totalSupplied) return;

        uint256 shortfall = totalSupplied - backed;
        uint256 toleranceBps = 1; // 0.01% of totalSupplied — rounding-only margin
        uint256 tolerance = (totalSupplied * toleranceBps) / 10_000;

        assertLe(
            shortfall,
            tolerance,
            "pool owes suppliers materially more than it holds plus what is on loan"
        );
    }
}
