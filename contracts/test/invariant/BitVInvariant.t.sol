// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseProtocolTest} from "../BaseProtocolTest.sol";
import {Handler} from "./Handler.sol";
import {IAPassComplianceValidator} from "../../src/interfaces/external/IAPassComplianceValidator.sol";

/**
 * @title BitVInvariantTest
 * @notice Handler-based invariant tests for the core pool/lending
 * engine (Build 03.5, Task 6). Covers the invariants explicitly named
 * in the milestone brief that are meaningfully checkable without
 * BitScore/vaults/RWA:
 *
 *   1. Borrowed liquidity can never exceed supplied liquidity.
 *   2. A pool's available liquidity plus its total debt is always at
 *      least its total supplied (i.e. the pool never owes out more
 *      underlying than it can account for, even after donations).
 *   3. Compliance-protected actions cannot bypass the compliance guard
 *      — checked directly (not via the handler) since it's a static
 *      property of construction, not something that emerges from a
 *      sequence of actions.
 *
 * Not attempted here as fuzzed invariants (documented as a known gap in
 * docs/economic-engine-review.md): per-user health-factor-never-
 * negative-appearing correctness across arbitrary multi-asset paths,
 * and liquidation-cannot-improve-an-unhealthy-position-incorrectly —
 * both are covered by the targeted scenario tests in
 * BitVLiquidation.t.sol instead, which assert exact expected values
 * rather than a general fuzzed property.
 */
contract BitVInvariantTest is BaseProtocolTest {
    Handler internal handler;

    function setUp() public override {
        super.setUp();

        address[] memory actors = new address[](3);
        actors[0] = supplier;
        actors[1] = borrower;
        actors[2] = liquidator;

        handler = new Handler(poolManager, lendingManager, debtAsset, collateralAsset, actors);

        // Give the handler's actors collateral headroom so `borrow` calls
        // aren't immediately rejected by zero collateral in every run —
        // deposit collateral for `borrower` up front (repeatable per-run
        // via the handler's own depositCollateral action too).
        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), type(uint256).max);
        lendingManager.depositCollateral(address(collateralAsset), 100e18);
        vm.stopPrank();

        targetContract(address(handler));
    }

    /// 1. Borrowed liquidity can never exceed supplied liquidity.
    function invariant_BorrowedNeverExceedsSupplied() public view {
        assertLe(poolManager.totalBorrowed(address(debtAsset)), poolManager.totalSupplied(address(debtAsset)));
    }

    /// 2. availableLiquidity + totalBorrowed >= totalSupplied: the pool
    /// can always account for what it owes suppliers, even with
    /// donations (which only ever add slack, never remove it).
    function invariant_LiquidityCoversSupply() public view {
        uint256 available = poolManager.availableLiquidity(address(debtAsset));
        uint256 borrowed = poolManager.totalBorrowed(address(debtAsset));
        uint256 supplied = poolManager.totalSupplied(address(debtAsset));
        assertGe(available + borrowed, supplied);
    }

    /// 3. Compliance-protected actions cannot bypass the compliance
    /// guard: a wallet the mock validator has never granted a CVI to
    /// cannot deposit, regardless of how much protocol state has
    /// accumulated from the handler's fuzzed actions.
    function invariant_UncompliantWalletStillRejected() public {
        address neverCompliant = makeAddr("neverCompliantFuzzTarget");
        debtAsset.mint(neverCompliant, 1e18);

        vm.startPrank(neverCompliant);
        debtAsset.approve(address(poolManager), 1e18);
        vm.expectRevert();
        poolManager.deposit(address(debtAsset), 1e18);
        vm.stopPrank();
    }
}
