// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseRWATest} from "../BaseRWATest.sol";
import {RWAHandler} from "./RWAHandler.sol";
import {BitVRWACollateralRegistry} from "../../src/core/BitVRWACollateralRegistry.sol";

/**
 * @title BitVRWAInvariantTest
 * @notice Handler-based invariant tests for the RWA collateral registry
 * (Build 06.1), covering docs/rwa-market-specification.md §18's
 * invariant list: unregistered assets never count as eligible collateral,
 * frozen assets never increase borrowing capacity, borrowing never
 * exceeds the hard LTV, oracle failure never increases borrowing
 * capacity, unauthorized users cannot register/modify, compliance
 * cannot be bypassed, collateral caps hold, and debt-asset restrictions
 * cannot be bypassed.
 */
contract BitVRWAInvariantTest is BaseRWATest {
    RWAHandler internal handler;

    function setUp() public override {
        super.setUp();

        address[] memory actors = new address[](3);
        actors[0] = supplier;
        actors[1] = borrower;
        actors[2] = liquidator;

        handler = new RWAHandler(
            lendingManager, poolManager, registry, oracle, collateralAsset, debtAsset, admin, actors
        );

        // Liquidity for the fuzzer's borrow/repay/liquidate actions.
        vm.startPrank(supplier);
        debtAsset.mint(supplier, 10_000_000e18);
        debtAsset.approve(address(poolManager), 10_000_000e18);
        poolManager.deposit(address(debtAsset), 10_000_000e18);
        vm.stopPrank();

        targetContract(address(handler));
    }

    /// 1. Unregistered assets never count as eligible RWA collateral —
    /// debtAsset was never registered with the registry.
    function invariant_UnregisteredAssetsNeverEligible() public view {
        assertFalse(registry.isRegisteredAsset(address(debtAsset)));
        assertFalse(registry.isEligibleForNewActivity(address(debtAsset)));
    }

    /// 2. Frozen assets never increase borrowing capacity: whenever the
    /// registry reports the RWA asset ineligible, every actor's
    /// effective available borrow value contributed by that asset must
    /// be zero (checked via the debt-asset-aware view, which is exactly
    /// what `borrow()` itself consults).
    function invariant_FrozenAssetsNeverIncreaseBorrowCapacity() public view {
        if (registry.isEligibleForNewActivity(address(collateralAsset))) return;

        address[3] memory actors = [supplier, borrower, liquidator];
        for (uint256 i = 0; i < actors.length; i++) {
            // Every actor's collateral is entirely in the (ineligible)
            // RWA asset in this fixture, so availableBorrowValue must be
            // exactly zero whenever it's ineligible.
            assertEq(lendingManager.getUserAccountDataForBorrow(actors[i], address(debtAsset)).availableBorrowValue, 0);
        }
    }

    /// 3. Borrowing never exceeds the hard LTV — re-derives the same
    /// ceiling BitVLendingManager itself enforces and checks the actual
    /// effective available value never exceeds it, for whatever fuzzed
    /// state exists.
    function invariant_BorrowingNeverExceedsHardLtv() public view {
        address[3] memory actors = [supplier, borrower, liquidator];
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 effective = lendingManager.getEffectiveAvailableBorrowValue(actors[i]);
            uint256 weightedMax = lendingManager.getUserAccountData(actors[i]).weightedMaxLtvValue;
            uint256 debtValue = lendingManager.getUserAccountData(actors[i]).totalDebtValue;
            uint256 ceiling = weightedMax > debtValue ? weightedMax - debtValue : 0;
            assertLe(effective, ceiling);
        }
    }

    /// 4. Oracle failure (zero/stale price) never increases borrowing
    /// capacity — forcing the price to zero mid-run must immediately
    /// zero out this asset's contribution to available borrow value.
    function invariant_OracleFailureNeverIncreasesBorrowCapacity() public {
        uint256 realPrice = COLLATERAL_PRICE;

        vm.prank(admin);
        oracle.setPrice(address(collateralAsset), 0, 18);
        assertFalse(registry.isEligibleForNewActivity(address(collateralAsset)));

        address[3] memory actors = [supplier, borrower, liquidator];
        for (uint256 i = 0; i < actors.length; i++) {
            assertEq(lendingManager.getUserAccountDataForBorrow(actors[i], address(debtAsset)).availableBorrowValue, 0);
        }

        // Restore, mirroring BitVInvariant.t.sol's
        // invariant_BitScoreFailureNeverMoreFavorableThanBase pattern —
        // this invariant's own probe must not permanently corrupt state
        // for subsequent invariant checks / fuzzed calls in the same run.
        vm.startPrank(admin);
        oracle.setPrice(address(collateralAsset), realPrice, 18);
        registry.markPriceFresh(address(collateralAsset));
        vm.stopPrank();
    }

    /// 5. Unauthorized users cannot register assets.
    function invariant_UnauthorizedUsersCannotRegisterAssets() public {
        vm.prank(borrower); // not RWA_ADMIN_ROLE
        vm.expectRevert();
        registry.registerAsset(
            address(0xBEEF),
            BitVRWACollateralRegistry.AssetConfigParams({
                ltvBps: 1,
                maxLtvWithScoreBps: 1,
                liquidationThresholdBps: 1,
                liquidationBonusBps: 0,
                collateralCap: 0,
                oracle: address(oracle),
                maxOracleStalenessSeconds: 1
            })
        );
    }

    /// 6. Unauthorized users cannot modify risk parameters.
    function invariant_UnauthorizedUsersCannotModifyRiskParams() public {
        vm.prank(borrower);
        vm.expectRevert();
        registry.setCollateralCap(address(collateralAsset), 0);
    }

    /// 7. Compliance cannot be bypassed, regardless of accumulated fuzz
    /// state.
    function invariant_ComplianceCannotBeBypassed() public {
        address neverCompliant = makeAddr("neverCompliantRwaFuzz");
        collateralAsset.mint(neverCompliant, 1e18);

        vm.startPrank(neverCompliant);
        collateralAsset.approve(address(lendingManager), 1e18);
        vm.expectRevert();
        lendingManager.depositCollateral(address(collateralAsset), 1e18);
        vm.stopPrank();
    }

    /// 8. Collateral caps cannot be exceeded — via NEW deposits, which
    /// is the only lever the cap actually controls. Note: lowering the
    /// cap below an already-deposited total does not forcibly evict
    /// existing depositors (the same supply-cap semantics used
    /// elsewhere in DeFi, e.g. a pool's own `supplyCap`) — so "total <=
    /// cap" is not itself an always-true invariant once a cap has been
    /// lowered retroactively; what must always hold, and what this
    /// checks directly, is that once total collateral is at or beyond
    /// the current cap, no further deposit can push it higher.
    function invariant_CollateralCapEnforcedGoingForward() public {
        uint256 cap = registry.getCollateralCap(address(collateralAsset));
        if (cap == 0) return; // uncapped
        uint256 total = lendingManager.getTotalCollateralByAsset(address(collateralAsset));
        if (total < cap) return; // headroom exists — nothing to prove here

        collateralAsset.mint(borrower, 1);
        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), 1);
        vm.expectRevert();
        lendingManager.depositCollateral(address(collateralAsset), 1);
        vm.stopPrank();
    }

    /// Also: the registry's cap can only ever have been changed via the
    /// handler's own tracked, authorized setter.
    function invariant_CollateralCapOnlyChangedByAuthorizedPath() public view {
        assertEq(registry.getCollateralCap(address(collateralAsset)), handler.ghostLastCap());
    }

    /// 9. Allowed debt-asset restrictions cannot be bypassed: with a
    /// restriction configured excluding debtAsset, no actor's
    /// available-borrow-value-for-debtAsset can be nonzero purely from
    /// the restricted RWA collateral.
    function invariant_AllowedDebtAssetRestrictionCannotBeBypassed() public {
        vm.prank(admin);
        registry.setAllowedDebtAsset(address(collateralAsset), address(debtAsset), false);
        vm.prank(admin);
        registry.setAllowedDebtAsset(address(collateralAsset), address(0xBEEF), true);

        assertFalse(registry.isDebtAssetAllowed(address(collateralAsset), address(debtAsset)));

        address[3] memory actors = [supplier, borrower, liquidator];
        for (uint256 i = 0; i < actors.length; i++) {
            assertEq(lendingManager.getUserAccountDataForBorrow(actors[i], address(debtAsset)).availableBorrowValue, 0);
        }

        // Restore unrestricted state so later invariant checks in the
        // same run aren't affected by this probe.
        vm.prank(admin);
        registry.setAllowedDebtAsset(address(collateralAsset), address(0xBEEF), false);
    }
}
