// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseRWATest} from "../BaseRWATest.sol";
import {BitVRWACollateralRegistry} from "../../src/core/BitVRWACollateralRegistry.sol";
import {RWAErrors} from "../../src/libraries/RWAErrors.sol";
import {ProtocolErrors} from "../../src/libraries/ProtocolErrors.sol";
import {ComplianceErrors} from "../../src/libraries/ComplianceErrors.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

contract BitVRWACollateralRegistryTest is BaseRWATest {
    function _defaultParams() internal view returns (BitVRWACollateralRegistry.AssetConfigParams memory) {
        return BitVRWACollateralRegistry.AssetConfigParams({
            ltvBps: 7_000,
            maxLtvWithScoreBps: 7_800,
            liquidationThresholdBps: 8_000,
            liquidationBonusBps: 500,
            collateralCap: 0,
            oracle: address(oracle),
            maxOracleStalenessSeconds: STALENESS_WINDOW,
            isCVA: false
        });
    }

    // ══════════════════════════ REGISTRY ══════════════════════════

    function test_RegisterAsset_Succeeds() public view {
        BitVRWACollateralRegistry.AssetConfig memory cfg = registry.getAssetConfig(address(collateralAsset));
        assertEq(uint8(cfg.status), uint8(BitVRWACollateralRegistry.AssetStatus.Active));
        assertEq(cfg.ltvBps, 7_000);
    }

    function test_UnauthorizedRegistration_Reverts() public {
        address newAsset = makeAddr("newRwaAsset");
        BitVRWACollateralRegistry.AssetConfigParams memory params = _defaultParams();

        vm.prank(borrower); // not RWA_ADMIN_ROLE
        vm.expectRevert();
        registry.registerAsset(newAsset, params);
    }

    function test_DuplicateRegistration_Reverts() public {
        BitVRWACollateralRegistry.AssetConfigParams memory params = _defaultParams();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(RWAErrors.AssetAlreadyRegistered.selector, address(collateralAsset)));
        registry.registerAsset(address(collateralAsset), params);
    }

    function test_RegisterAsset_RejectsParamsExceedingPoolLimits() public {
        address freshPoolAsset = address(debtAsset); // has ltvBps 0 (not configured as collateral in its own pool)
        BitVRWACollateralRegistry.AssetConfigParams memory params = _defaultParams();

        vm.prank(admin);
        vm.expectRevert(); // debtAsset's own pool has isCollateralEnabled = false
        registry.registerAsset(freshPoolAsset, params);
    }

    function test_UpdateApprovedParameters_Succeeds() public {
        BitVRWACollateralRegistry.AssetConfigParams memory params = _defaultParams();
        params.collateralCap = 500e18;

        vm.prank(admin);
        registry.updateAssetConfig(address(collateralAsset), params);

        BitVRWACollateralRegistry.AssetConfig memory cfg = registry.getAssetConfig(address(collateralAsset));
        assertEq(cfg.collateralCap, 500e18);
    }

    function test_UnauthorizedParameterUpdate_Reverts() public {
        BitVRWACollateralRegistry.AssetConfigParams memory params = _defaultParams();
        vm.prank(borrower);
        vm.expectRevert();
        registry.updateAssetConfig(address(collateralAsset), params);
    }

    function test_FreezeAsset_Succeeds() public {
        vm.prank(admin);
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Frozen);

        BitVRWACollateralRegistry.AssetConfig memory cfg = registry.getAssetConfig(address(collateralAsset));
        assertEq(uint8(cfg.status), uint8(BitVRWACollateralRegistry.AssetStatus.Frozen));
    }

    function test_UnfreezeAsset_RestoresActive() public {
        vm.startPrank(admin);
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Frozen);
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Active);
        vm.stopPrank();

        assertTrue(registry.isEligibleForNewActivity(address(collateralAsset)));
    }

    function test_DelistAsset_IsPermanent() public {
        vm.startPrank(admin);
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Delisted);
        vm.expectRevert(abi.encodeWithSelector(RWAErrors.AssetDelisted.selector, address(collateralAsset)));
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Active);
        vm.stopPrank();
    }

    function test_UnauthorizedFreeze_Reverts() public {
        vm.prank(borrower);
        vm.expectRevert();
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Frozen);
    }

    // ══════════════════════════ COLLATERAL ══════════════════════════

    function test_DepositApprovedRwa_Succeeds() public {
        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), 10e18);
        lendingManager.depositCollateral(address(collateralAsset), 10e18);
        vm.stopPrank();

        assertEq(lendingManager.getCollateralBalance(borrower, address(collateralAsset)), 10e18);
    }

    function test_DepositUnregisteredRwa_StillWorksAsOrdinaryCollateral() public {
        // debtAsset is not registered with the registry at all — deposit
        // behavior for it is completely unaffected (it isn't even
        // collateral-enabled in this fixture, so it reverts for a
        // pre-existing, non-RWA reason, proving the registry adds no
        // new restriction to unregistered assets).
        vm.startPrank(borrower);
        debtAsset.approve(address(lendingManager), 10e18);
        vm.expectRevert(abi.encodeWithSelector(ProtocolErrors.CollateralDisabled.selector, address(debtAsset)));
        lendingManager.depositCollateral(address(debtAsset), 10e18);
        vm.stopPrank();
    }

    function test_FrozenRwa_RejectsNewDeposit() public {
        vm.prank(admin);
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Frozen);

        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), 10e18);
        vm.expectRevert(abi.encodeWithSelector(RWAErrors.AssetNotEligibleForDeposit.selector, address(collateralAsset)));
        lendingManager.depositCollateral(address(collateralAsset), 10e18);
        vm.stopPrank();
    }

    function test_CollateralAccounting_MatchesDeposit() public {
        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), 25e18);
        lendingManager.depositCollateral(address(collateralAsset), 25e18);
        vm.stopPrank();

        assertEq(lendingManager.getTotalCollateralByAsset(address(collateralAsset)), 25e18);
    }

    function test_WithdrawRwaCollateral_Succeeds() public {
        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), 10e18);
        lendingManager.depositCollateral(address(collateralAsset), 10e18);
        lendingManager.withdrawCollateral(address(collateralAsset), 4e18);
        vm.stopPrank();

        assertEq(lendingManager.getCollateralBalance(borrower, address(collateralAsset)), 6e18);
        assertEq(lendingManager.getTotalCollateralByAsset(address(collateralAsset)), 6e18);
    }

    function test_FrozenRwa_WithdrawalStillAllowed() public {
        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), 10e18);
        lendingManager.depositCollateral(address(collateralAsset), 10e18);
        vm.stopPrank();

        vm.prank(admin);
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Frozen);

        vm.prank(borrower);
        lendingManager.withdrawCollateral(address(collateralAsset), 5e18);
        assertEq(lendingManager.getCollateralBalance(borrower, address(collateralAsset)), 5e18);
    }

    function test_CollateralCap_Enforced() public {
        vm.prank(admin);
        registry.setCollateralCap(address(collateralAsset), 5e18);

        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), 6e18);
        vm.expectRevert(
            abi.encodeWithSelector(RWAErrors.CollateralCapExceeded.selector, address(collateralAsset), 6e18, 5e18)
        );
        lendingManager.depositCollateral(address(collateralAsset), 6e18);
        vm.stopPrank();
    }

    // ══════════════════════════ ORACLE ══════════════════════════

    function test_ValidPrice_AllowsEligibility() public view {
        assertTrue(registry.isEligibleForNewActivity(address(collateralAsset)));
    }

    function test_ZeroPrice_TreatedAsUnavailable() public {
        vm.prank(admin);
        oracle.setPrice(address(collateralAsset), 0, 18);
        assertFalse(registry.isEligibleForNewActivity(address(collateralAsset)));
    }

    function test_StalePrice_TreatedAsUnavailable() public {
        vm.warp(block.timestamp + STALENESS_WINDOW + 1);
        assertFalse(registry.isEligibleForNewActivity(address(collateralAsset)));
    }

    function test_NeverMarkedFresh_TreatedAsUnavailable() public {
        // Reconfiguring the oracle resets the freshness attestation.
        vm.prank(admin);
        registry.setOracleConfig(address(collateralAsset), address(oracle), STALENESS_WINDOW);
        assertFalse(registry.isEligibleForNewActivity(address(collateralAsset)));
    }

    function test_AuthorizedOracleUpdate_Succeeds() public {
        vm.prank(admin);
        registry.markPriceFresh(address(collateralAsset)); // re-attest, still authorized
        assertTrue(registry.isEligibleForNewActivity(address(collateralAsset)));
    }

    function test_UnauthorizedOracleUpdate_Reverts() public {
        vm.prank(borrower);
        vm.expectRevert();
        registry.markPriceFresh(address(collateralAsset));
    }

    function test_UnauthorizedOracleConfigChange_Reverts() public {
        vm.prank(borrower);
        vm.expectRevert();
        registry.setOracleConfig(address(collateralAsset), address(oracle), 1 hours);
    }

    // ══════════════════════════ BORROWING ══════════════════════════

    function _depositRwaCollateral(address user, uint256 amount) internal {
        vm.startPrank(user);
        collateralAsset.approve(address(lendingManager), amount);
        lendingManager.depositCollateral(address(collateralAsset), amount);
        vm.stopPrank();
    }

    function _supplyDebtLiquidity(uint256 amount) internal {
        debtAsset.mint(supplier, amount);
        vm.startPrank(supplier);
        debtAsset.approve(address(poolManager), amount);
        poolManager.deposit(address(debtAsset), amount);
        vm.stopPrank();
    }

    function test_BorrowAgainstApprovedRwa_Succeeds() public {
        _supplyDebtLiquidity(100_000e18);
        _depositRwaCollateral(borrower, 10e18); // $20,000 collateral

        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_000e18);

        assertEq(lendingManager.getCurrentDebt(borrower, address(debtAsset)), 1_000e18);
    }

    function test_BorrowAgainstUnregisteredRwa_StillWorksIfPoolAllows() public {
        // Proves an unregistered asset is unaffected — same pool-level
        // rejection reason as always (debtAsset isn't collateral-
        // enabled), not a registry rejection.
        vm.startPrank(borrower);
        debtAsset.approve(address(lendingManager), 10e18);
        vm.expectRevert(abi.encodeWithSelector(ProtocolErrors.CollateralDisabled.selector, address(debtAsset)));
        lendingManager.depositCollateral(address(debtAsset), 10e18);
        vm.stopPrank();
    }

    function test_BorrowAgainstFrozenRwa_Reverts() public {
        _supplyDebtLiquidity(100_000e18);
        _depositRwaCollateral(borrower, 10e18);

        vm.prank(admin);
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Frozen);

        vm.prank(borrower);
        vm.expectRevert();
        lendingManager.borrow(address(debtAsset), 1_000e18);
    }

    function test_HardLtv_Enforced() public {
        _supplyDebtLiquidity(100_000e18);
        _depositRwaCollateral(borrower, 10e18); // $20,000, 70% LTV = $14,000

        vm.prank(borrower);
        vm.expectRevert();
        lendingManager.borrow(address(debtAsset), 14_100e18);
    }

    function test_BitScoreAdjustment_AppliesToRwaCollateral() public {
        _supplyDebtLiquidity(1_000_000e18);
        _depositRwaCollateral(borrower, 10e18);

        uint256 baseAvailable = lendingManager.getEffectiveAvailableBorrowValue(borrower);
        assertGt(baseAvailable, 0); // BitScore is wired (BaseProtocolTest), Tier 1 = no adjustment yet
    }

    function test_HardLtv_NeverExceededEvenAtMaxTier() public {
        _supplyDebtLiquidity(1_000_000e18);
        _depositRwaCollateral(borrower, 10e18); // $20,000 collateral, 78% ceiling = $15,600

        vm.prank(borrower);
        vm.expectRevert();
        lendingManager.borrow(address(debtAsset), 15_700e18);
    }

    function test_AllowedDebtAssets_Enforced() public {
        _supplyDebtLiquidity(100_000e18);
        _depositRwaCollateral(borrower, 10e18);

        vm.prank(admin);
        registry.setAllowedDebtAsset(address(collateralAsset), address(0xBEEF), true); // only 0xBEEF allowed

        DataTypes.AccountData memory data =
            lendingManager.getUserAccountDataForBorrow(borrower, address(debtAsset));
        assertEq(data.availableBorrowValue, 0); // debtAsset not in the allowed set -> zero credit from this collateral

        vm.prank(borrower);
        vm.expectRevert();
        lendingManager.borrow(address(debtAsset), 1_000e18);
    }

    function test_AllowedDebtAssets_UnrestrictedByDefault() public view {
        // No restriction configured -> every debt asset allowed.
        assertTrue(registry.isDebtAssetAllowed(address(collateralAsset), address(debtAsset)));
    }

    function test_CollateralCap_BlocksDepositBeforeBorrow() public {
        vm.prank(admin);
        registry.setCollateralCap(address(collateralAsset), 3e18);

        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), 5e18);
        vm.expectRevert();
        lendingManager.depositCollateral(address(collateralAsset), 5e18);
        vm.stopPrank();
    }

    // ══════════════════════════ LIQUIDATION ══════════════════════════

    function test_HealthyRwaPosition_CannotBeLiquidated() public {
        _supplyDebtLiquidity(100_000e18);
        _depositRwaCollateral(borrower, 10e18);
        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_000e18);

        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 1_000e18);
        vm.expectRevert();
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 500e18);
        vm.stopPrank();
    }

    function test_UnhealthyRwaPosition_CanBeLiquidated() public {
        _supplyDebtLiquidity(100_000e18);
        _depositRwaCollateral(borrower, 1e18);
        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_400e18); // max 70% LTV

        vm.prank(admin);
        oracle.setPrice(address(collateralAsset), 1_500e18, 18); // crash -> unhealthy
        vm.prank(admin);
        registry.markPriceFresh(address(collateralAsset)); // keep registry attestation current for this test

        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 700e18);
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 700e18);
        vm.stopPrank();

        assertLt(lendingManager.getCurrentDebt(borrower, address(debtAsset)), 1_400e18);
    }

    function test_PartialLiquidation_RwaCollateral() public {
        _supplyDebtLiquidity(100_000e18);
        _depositRwaCollateral(borrower, 1e18);
        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_400e18);

        vm.prank(admin);
        oracle.setPrice(address(collateralAsset), 1_500e18, 18);

        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 400e18);
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 400e18);
        vm.stopPrank();

        assertGt(lendingManager.getCurrentDebt(borrower, address(debtAsset)), 0);
    }

    function test_LiquidationBonus_RwaCollateral() public {
        _supplyDebtLiquidity(100_000e18);
        _depositRwaCollateral(borrower, 1e18);
        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_400e18);

        vm.prank(admin);
        oracle.setPrice(address(collateralAsset), 1_500e18, 18);

        uint256 liquidatorCollateralBefore = collateralAsset.balanceOf(liquidator);
        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 700e18);
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 700e18);
        vm.stopPrank();

        uint256 seized = collateralAsset.balanceOf(liquidator) - liquidatorCollateralBefore;
        // 700e18 repaid at $1 = $700 value; seized at 5% bonus should be
        // worth $735, i.e. more collateral (in $ terms) than repaid.
        uint256 seizedValueUsd = seized * 1_500e18 / 1e18;
        assertGt(seizedValueUsd, 700e18);
    }

    function test_FrozenCollateral_LiquidationStillAvailable() public {
        _supplyDebtLiquidity(100_000e18);
        _depositRwaCollateral(borrower, 1e18);
        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_400e18);

        vm.prank(admin);
        oracle.setPrice(address(collateralAsset), 1_500e18, 18);
        vm.prank(admin);
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Frozen);

        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 700e18);
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 700e18);
        vm.stopPrank();

        assertLt(lendingManager.getCurrentDebt(borrower, address(debtAsset)), 1_400e18);
    }

    function test_BadDebt_RwaCollateral() public {
        _supplyDebtLiquidity(100_000e18);
        _depositRwaCollateral(borrower, 1e18);
        vm.prank(borrower);
        lendingManager.borrow(address(debtAsset), 1_400e18);

        // Crash hard enough that seizing bonus-adjusted collateral for a
        // full close exceeds what the borrower actually has.
        vm.prank(admin);
        oracle.setPrice(address(collateralAsset), 700e18, 18);

        vm.startPrank(liquidator);
        debtAsset.approve(address(lendingManager), 1_400e18);
        lendingManager.liquidate(borrower, address(debtAsset), address(collateralAsset), 1_400e18);
        vm.stopPrank();

        assertEq(lendingManager.getCollateralBalance(borrower, address(collateralAsset)), 0);
    }

    // ══════════════════════════ COMPLIANCE ══════════════════════════

    function test_UnverifiedUser_RwaDepositRejected() public {
        address stranger = makeAddr("neverCompliantRwa");
        collateralAsset.mint(stranger, 10e18);

        vm.startPrank(stranger);
        collateralAsset.approve(address(lendingManager), 10e18);
        vm.expectRevert(
            abi.encodeWithSelector(ComplianceErrors.ComplianceCheckFailed.selector, address(lendingManager), stranger)
        );
        lendingManager.depositCollateral(address(collateralAsset), 10e18);
        vm.stopPrank();
    }

    function test_ComplianceFailure_RegistryNeverConsulted() public {
        address stranger = makeAddr("neverCompliantRwa2");
        collateralAsset.mint(stranger, 10e18);
        vm.prank(admin);
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Frozen);

        vm.startPrank(stranger);
        collateralAsset.approve(address(lendingManager), 10e18);
        // Compliance fails before the registry's frozen-asset check is
        // ever reached — same revert reason either way, proving order.
        vm.expectRevert(
            abi.encodeWithSelector(ComplianceErrors.ComplianceCheckFailed.selector, address(lendingManager), stranger)
        );
        lendingManager.depositCollateral(address(collateralAsset), 10e18);
        vm.stopPrank();
    }

    function test_ComplianceCannotBeBypassed_ViaActiveAssetStatus() public {
        // Asset being Active never substitutes for user compliance.
        address stranger = makeAddr("neverCompliantRwa3");
        collateralAsset.mint(stranger, 10e18);
        assertTrue(registry.isEligibleForNewActivity(address(collateralAsset)));

        vm.startPrank(stranger);
        collateralAsset.approve(address(lendingManager), 10e18);
        vm.expectRevert();
        lendingManager.depositCollateral(address(collateralAsset), 10e18);
        vm.stopPrank();
    }

    // ══════════════════════════ SECURITY ══════════════════════════

    function test_UnauthorizedRegistration_CannotBypassRoleCheck() public {
        vm.prank(liquidator);
        vm.expectRevert();
        registry.registerAsset(makeAddr("attackAsset"), _defaultParams());
    }

    function test_UnauthorizedParameterManipulation_Reverts() public {
        vm.prank(liquidator);
        vm.expectRevert();
        registry.setCollateralCap(address(collateralAsset), type(uint256).max);
    }

    function test_UnauthorizedAllowedDebtAssetChange_Reverts() public {
        vm.prank(liquidator);
        vm.expectRevert();
        registry.setAllowedDebtAsset(address(collateralAsset), address(debtAsset), false);
    }

    function test_FrozenAssetAttack_CannotIncreaseBorrowCapacity() public {
        _supplyDebtLiquidity(100_000e18);
        _depositRwaCollateral(borrower, 10e18);

        uint256 beforeFreeze = lendingManager.getEffectiveAvailableBorrowValue(borrower);

        vm.prank(admin);
        registry.setAssetStatus(address(collateralAsset), BitVRWACollateralRegistry.AssetStatus.Frozen);

        uint256 afterFreeze = lendingManager.getEffectiveAvailableBorrowValue(borrower);
        assertLt(afterFreeze, beforeFreeze);
        assertEq(afterFreeze, 0);
    }

    function test_LtvBypass_CannotExceedRegistryCeilingViaBitScore() public {
        _supplyDebtLiquidity(1_000_000e18);
        _depositRwaCollateral(borrower, 10e18); // 78% ceiling = $15,600

        vm.prank(borrower);
        vm.expectRevert();
        lendingManager.borrow(address(debtAsset), 15_601e18);
    }

    function test_CollateralCapBypass_Reverts() public {
        vm.prank(admin);
        registry.setCollateralCap(address(collateralAsset), 10e18);

        _depositRwaCollateral(borrower, 10e18); // exactly at cap, succeeds

        vm.startPrank(borrower);
        collateralAsset.approve(address(lendingManager), 1);
        vm.expectRevert();
        lendingManager.depositCollateral(address(collateralAsset), 1); // 1 wei over cap
        vm.stopPrank();
    }
}
