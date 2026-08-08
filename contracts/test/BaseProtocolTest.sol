// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BitVAccessManager} from "../src/core/BitVAccessManager.sol";
import {BitVTreasury} from "../src/core/BitVTreasury.sol";
import {BitVPoolManager} from "../src/core/BitVPoolManager.sol";
import {BitVLendingManager} from "../src/core/BitVLendingManager.sol";
import {BitScoreManager} from "../src/core/BitScoreManager.sol";
import {StaticPriceOracle} from "../src/oracles/StaticPriceOracle.sol";
import {KinkedInterestRateModel} from "../src/oracles/KinkedInterestRateModel.sol";
import {MockComplianceValidator} from "./mocks/MockComplianceValidator.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IAPassComplianceValidator} from "../src/interfaces/external/IAPassComplianceValidator.sol";

/// @notice Shared fixture for BitVPoolManager / BitVLendingManager tests:
/// deploys the access manager, treasury, compliance mock, two mock
/// assets (a "supply/debt" asset and a "collateral" asset), a static
/// oracle, and a kinked interest rate model, then wires two pools.
abstract contract BaseProtocolTest is Test {
    BitVAccessManager internal accessManager;
    BitVTreasury internal treasury;
    MockComplianceValidator internal validator;
    BitVPoolManager internal poolManager;
    BitVLendingManager internal lendingManager;
    BitScoreManager internal bitScoreManager;
    StaticPriceOracle internal oracle;
    KinkedInterestRateModel internal rateModel;

    MockERC20 internal debtAsset; // e.g. a USD-stable debt/supply asset
    MockERC20 internal collateralAsset; // e.g. a volatile collateral asset

    address internal admin = makeAddr("admin");
    address internal owner = makeAddr("owner"); // Cleanverse rule-management owner
    address internal supplier = makeAddr("supplier");
    address internal borrower = makeAddr("borrower");
    address internal liquidator = makeAddr("liquidator");

    bytes2 internal constant GROUP_RETAIL = bytes2("rt");
    bytes2 internal constant SUBGROUP_STANDARD = bytes2("st");
    uint8 internal constant TIER_1 = 1;

    uint256 internal constant DEBT_PRICE = 1e18; // $1.00, 18 decimals
    uint256 internal constant COLLATERAL_PRICE = 2000e18; // $2000.00, 18 decimals

    function setUp() public virtual {
        vm.warp(1_700_000_000);

        validator = new MockComplianceValidator();
        accessManager = new BitVAccessManager(admin);
        treasury = new BitVTreasury(address(accessManager));

        debtAsset = new MockERC20("BitV Debt Asset", "bvUSD", 18);
        collateralAsset = new MockERC20("BitV Collateral Asset", "bvETH", 18);

        oracle = new StaticPriceOracle(admin);
        vm.startPrank(admin);
        oracle.setPrice(address(debtAsset), DEBT_PRICE, 18);
        oracle.setPrice(address(collateralAsset), COLLATERAL_PRICE, 18);
        vm.stopPrank();

        rateModel = new KinkedInterestRateModel(admin, 0, 4e25, 75e25, 80e25);

        poolManager = new BitVPoolManager(address(validator), owner, address(accessManager), address(treasury));
        lendingManager = new BitVLendingManager(
            address(validator), owner, address(accessManager), address(poolManager), address(treasury)
        );

        vm.startPrank(admin);
        poolManager.createPool(
            address(debtAsset),
            BitVPoolManager.PoolConfigParams({
                ltvBps: 0,
                maxLtvWithScoreBps: 0,
                liquidationThresholdBps: 0,
                liquidationBonusBps: 0,
                reserveFactorBps: 1_000, // 10% of interest to treasury
                supplyCap: 0,
                borrowCap: 0,
                interestRateModel: address(rateModel),
                priceOracle: address(oracle),
                isBorrowingEnabled: true,
                isCollateralEnabled: false
            })
        );
        poolManager.createPool(
            address(collateralAsset),
            BitVPoolManager.PoolConfigParams({
                ltvBps: 7_000, // 70% base LTV
                maxLtvWithScoreBps: 7_800, // 78% absolute BitScore ceiling, still under the 80% threshold
                liquidationThresholdBps: 8_000, // 80%
                liquidationBonusBps: 500, // +5%
                reserveFactorBps: 0,
                supplyCap: 0,
                borrowCap: 0,
                interestRateModel: address(0),
                priceOracle: address(oracle),
                isBorrowingEnabled: false,
                isCollateralEnabled: true
            })
        );
        poolManager.setLendingManager(address(lendingManager));
        vm.stopPrank();

        bitScoreManager = new BitScoreManager(address(accessManager));
        vm.startPrank(admin);
        bitScoreManager.setLendingManager(address(lendingManager));
        lendingManager.setBitScoreManager(address(bitScoreManager));
        vm.stopPrank();

        // Grant every actor the same permissive CVI rule by default so
        // tests focus on pool/lending logic; compliance-specific tests
        // override this per-user.
        _grantCompliantCvi(supplier);
        _grantCompliantCvi(borrower);
        _grantCompliantCvi(liquidator);

        debtAsset.mint(supplier, 1_000_000e18);
        debtAsset.mint(liquidator, 1_000_000e18);
        collateralAsset.mint(borrower, 1_000e18);
    }

    function _permissiveRule() internal pure returns (IAPassComplianceValidator.RuleV2 memory) {
        return IAPassComplianceValidator.RuleV2({
            allowedGroup: GROUP_RETAIL,
            allowedSubGroup: SUBGROUP_STANDARD,
            minTier: TIER_1,
            minSubTier: 0,
            poolCountryBitmap: 0 // unrestricted
        });
    }

    function _grantCompliantCvi(address user) internal {
        validator.setUser(user, GROUP_RETAIL, SUBGROUP_STANDARD, TIER_1, 0, 0);

        IAPassComplianceValidator.RuleV2[] memory rules = new IAPassComplianceValidator.RuleV2[](1);
        rules[0] = _permissiveRule();
        validator.setRules(address(poolManager), rules);
        validator.setRules(address(lendingManager), rules);
    }
}
