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

        handler = new Handler(poolManager, lendingManager, treasury, debtAsset, collateralAsset, actors, admin);

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

    /// Prompt 14: the treasury's reserve claims (interleaved by the
    /// handler with ordinary supply/borrow/repay activity) can never
    /// push the pool insolvent — its accrued-but-unclaimed reserve
    /// balance is always covered by the pool's own accounting the same
    /// way any other supplier's balance is, and never exceeds total
    /// supply.
    function invariant_TreasuryReserveNeverExceedsTotalSupply() public view {
        assertLe(poolManager.reserveBalance(address(debtAsset)), poolManager.totalSupplied(address(debtAsset)));
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

    // ── BitScore invariants (Build 04) ──────────────────────────────────
    // The handler's fuzzed deposit/withdraw/depositCollateral/borrow/
    // repay actions already drive BitScoreManager under the hood (it's
    // wired by default in BaseProtocolTest), so no separate BitScore-
    // specific handler actions are needed — these invariants check
    // BitScoreManager's own guarantees hold after whatever sequence of
    // real lending activity the fuzzer produced.

    /// Score never exceeds the documented maximum, for every actor,
    /// after any sequence of fuzzed activity.
    function invariant_ScoreNeverExceedsMax() public view {
        assertLe(bitScoreManager.getScore(supplier), 100);
        assertLe(bitScoreManager.getScore(borrower), 100);
        assertLe(bitScoreManager.getScore(liquidator), 100);
    }

    /// Score never falls below the documented minimum. Trivially true
    /// for a uint16 return value, but asserted explicitly (`>= 0` is
    /// always true for an unsigned type) to document the intent and
    /// catch a future refactor that widens the type incorrectly.
    function invariant_ScoreNeverBelowMin() public view {
        assertGe(uint256(bitScoreManager.getScore(supplier)), 0);
        assertGe(uint256(bitScoreManager.getScore(borrower)), 0);
        assertGe(uint256(bitScoreManager.getScore(liquidator)), 0);
    }

    /// Unauthorized users cannot increase their own (or anyone else's)
    /// score: only the registered lendingManager may call `record*`.
    function invariant_UnauthorizedCallerCannotIncreaseScore() public {
        uint16 before = bitScoreManager.getScore(borrower);
        vm.prank(borrower); // not the registered lendingManager
        vm.expectRevert();
        bitScoreManager.recordRepayment(borrower, true, 999 days);
        assertEq(bitScoreManager.getScore(borrower), before);
    }

    /// BitScore's LTV adjustment can never push a user's effective
    /// available-borrow-value above the asset-configured
    /// maxLtvWithScoreBps ceiling, for whatever collateral/debt state
    /// the fuzzer has produced — the same defense-in-depth clamp
    /// `_effectiveAvailableBorrowValue` applies is re-checked here
    /// independently, not just trusted by construction.
    function invariant_ScoreCannotExceedConfiguredLtvCeiling() public view {
        address[3] memory actors = [supplier, borrower, liquidator];
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 effective = lendingManager.getEffectiveAvailableBorrowValue(actors[i]);
            uint256 weightedMax = lendingManager.getUserAccountData(actors[i]).weightedMaxLtvValue;
            uint256 debtValue = lendingManager.getUserAccountData(actors[i]).totalDebtValue;
            uint256 ceiling = weightedMax > debtValue ? weightedMax - debtValue : 0;
            assertLe(effective, ceiling);
        }
    }

    /// If BitScore is disabled mid-run, every actor's effective
    /// available-borrow-value must exactly equal the base
    /// (score-independent) figure — never something more favorable, per
    /// the fail-safe requirement in docs/bitscore-specification.md §12.
    function invariant_BitScoreFailureNeverMoreFavorableThanBase() public {
        vm.prank(admin);
        lendingManager.setBitScoreManager(address(0));

        address[3] memory actors = [supplier, borrower, liquidator];
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 base = lendingManager.getUserAccountData(actors[i]).availableBorrowValue;
            uint256 effective = lendingManager.getEffectiveAvailableBorrowValue(actors[i]);
            assertEq(effective, base);
        }

        vm.prank(admin);
        lendingManager.setBitScoreManager(address(bitScoreManager));
    }
}
