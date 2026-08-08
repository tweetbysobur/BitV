// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseProtocolTest} from "./BaseProtocolTest.sol";
import {BitVRWACollateralRegistry} from "../src/core/BitVRWACollateralRegistry.sol";
import {BitVCVAAdapter} from "../src/core/BitVCVAAdapter.sol";

/// @notice Shared fixture for BitVRWACollateralRegistry tests. Extends
/// BaseProtocolTest so the full pool/lending/BitScore setup (including
/// `collateralAsset`'s pool: 70% ltvBps, 78% maxLtvWithScoreBps, 80%
/// liquidationThresholdBps, 5% liquidationBonusBps) is already in
/// place, then deploys the registry and registers `collateralAsset`
/// itself as RWA collateral, mirroring the pool's own risk parameters
/// exactly (the registry can only ever be equally or more conservative
/// than the pool, never looser — see
/// BitVRWACollateralRegistry._validateAgainstPool). Also deploys and
/// wires a BitVCVAAdapter (Build 07.1) — harmless for non-CVA tests
/// (no asset is admin-attested or policy-configured by default, so
/// every CVA-status query returns `false` until a test explicitly
/// configures one).
abstract contract BaseRWATest is BaseProtocolTest {
    BitVRWACollateralRegistry internal registry;
    BitVCVAAdapter internal cvaAdapter;

    uint32 internal constant STALENESS_WINDOW = 1 days;

    function setUp() public virtual override {
        super.setUp();

        registry = new BitVRWACollateralRegistry(address(accessManager), address(poolManager));
        cvaAdapter = new BitVCVAAdapter(address(accessManager));

        vm.startPrank(admin);
        lendingManager.setRwaRegistry(address(registry));
        registry.setCVAAdapter(address(cvaAdapter));
        registry.registerAsset(
            address(collateralAsset),
            BitVRWACollateralRegistry.AssetConfigParams({
                ltvBps: 7_000,
                maxLtvWithScoreBps: 7_800,
                liquidationThresholdBps: 8_000,
                liquidationBonusBps: 500,
                collateralCap: 0, // uncapped by default; specific tests override
                oracle: address(oracle),
                maxOracleStalenessSeconds: STALENESS_WINDOW
            })
        );
        registry.markPriceFresh(address(collateralAsset));
        vm.stopPrank();
    }

    function _registeredAsset() internal view returns (address) {
        return address(collateralAsset);
    }
}
