// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BitVAccessManager} from "../src/core/BitVAccessManager.sol";
import {BitVTreasury} from "../src/core/BitVTreasury.sol";
import {BitVYieldVault} from "../src/core/BitVYieldVault.sol";
import {TestYieldStrategy} from "../src/vault/TestYieldStrategy.sol";
import {MockComplianceValidator} from "./mocks/MockComplianceValidator.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IAPassComplianceValidator} from "../src/interfaces/external/IAPassComplianceValidator.sol";

/// @notice Shared fixture for BitVYieldVault tests: access manager,
/// treasury, compliance mock, one mock underlying asset, a deployed
/// vault (uncapped, minDeposit = 1e6), and a TestYieldStrategy not yet
/// wired in as the active strategy (tests that need it call
/// `_setActiveStrategy()`).
abstract contract BaseVaultTest is Test {
    BitVAccessManager internal accessManager;
    BitVTreasury internal treasury;
    MockComplianceValidator internal validator;
    MockERC20 internal underlying;
    BitVYieldVault internal vault;
    TestYieldStrategy internal strategy;

    address internal admin = makeAddr("admin");
    address internal complianceOwner = makeAddr("complianceOwner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal unverified = makeAddr("unverified");

    bytes2 internal constant GROUP_RETAIL = bytes2("rt");
    bytes2 internal constant SUBGROUP_STANDARD = bytes2("st");
    uint8 internal constant TIER_1 = 1;

    uint256 internal constant MIN_DEPOSIT = 1e6;
    uint256 internal constant VAULT_CAP = 100_000_000e18;

    function setUp() public virtual {
        vm.warp(1_700_000_000);

        validator = new MockComplianceValidator();
        accessManager = new BitVAccessManager(admin);
        treasury = new BitVTreasury(address(accessManager));
        underlying = new MockERC20("BitV Vault Asset", "bvVLT", 18);

        vault = new BitVYieldVault(
            underlying,
            "BitV Yield Vault Share",
            "bvyVLT",
            address(validator),
            complianceOwner,
            address(accessManager),
            address(treasury),
            VAULT_CAP,
            MIN_DEPOSIT
        );

        strategy = new TestYieldStrategy(address(underlying), address(vault), true);

        _grantCompliantCvi(alice);
        _grantCompliantCvi(bob);

        underlying.mint(alice, 10_000_000e18);
        underlying.mint(bob, 10_000_000e18);
        underlying.mint(unverified, 10_000_000e18);
    }

    function _permissiveRule() internal pure returns (IAPassComplianceValidator.RuleV2 memory) {
        return IAPassComplianceValidator.RuleV2({
            allowedGroup: GROUP_RETAIL,
            allowedSubGroup: SUBGROUP_STANDARD,
            minTier: TIER_1,
            minSubTier: 0,
            poolCountryBitmap: 0
        });
    }

    function _grantCompliantCvi(address user) internal {
        validator.setUser(user, GROUP_RETAIL, SUBGROUP_STANDARD, TIER_1, 0, 0);
        IAPassComplianceValidator.RuleV2[] memory rules = new IAPassComplianceValidator.RuleV2[](1);
        rules[0] = _permissiveRule();
        validator.setRules(address(vault), rules);
    }

    function _setActiveStrategy() internal {
        vm.startPrank(admin);
        vault.setStrategy(address(strategy));
        vault.setMaxStrategyAllocationBps(10_000);
        vault.setMinIdleReserveBps(0);
        vm.stopPrank();
    }

    function _depositAs(address user, uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        underlying.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }
}
