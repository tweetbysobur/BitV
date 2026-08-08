// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { ProtocolRegistry } from "../src/core/ProtocolRegistry.sol";
import { AccessManager } from "../src/core/AccessManager.sol";
import { BitScoreManager } from "../src/core/BitScoreManager.sol";
import { Treasury } from "../src/core/Treasury.sol";
import { PoolManager } from "../src/core/PoolManager.sol";
import { LendingManager } from "../src/core/LendingManager.sol";
import { VaultManager } from "../src/core/VaultManager.sol";
import { StaticPriceOracle } from "../src/oracles/StaticPriceOracle.sol";
import { KinkedInterestRateModel } from "../src/oracles/KinkedInterestRateModel.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockIdentityOracle } from "./mocks/MockIdentityOracle.sol";
import { DataTypes } from "../src/libraries/DataTypes.sol";
import { WadRayMath } from "../src/libraries/WadRayMath.sol";
import { IAccessManager } from "../src/interfaces/IAccessManager.sol";
import { IIdentityOracle } from "../src/interfaces/IIdentityOracle.sol";

/// @notice Deploys the full BitV protocol suite behind proxies, wired
///         together exactly as `script/Deploy.s.sol` would in production —
///         every test in this suite exercises the real deployment topology,
///         not a simplified stand-in for it.
abstract contract BaseTest is Test {
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal liquidator = makeAddr("liquidator");

    address internal lendingPool = makeAddr("lendingValidatorPool");
    address internal borrowingPool = makeAddr("borrowingValidatorPool");
    address internal poolsPool = makeAddr("poolsValidatorPool");
    address internal vaultsPool = makeAddr("vaultsValidatorPool");

    ProtocolRegistry internal registry;
    AccessManager internal accessManager;
    BitScoreManager internal bitScoreManager;
    Treasury internal treasury;
    PoolManager internal poolManager;
    LendingManager internal lendingManager;
    VaultManager internal vaultManager;
    StaticPriceOracle internal priceOracle;
    MockIdentityOracle internal identityOracle;
    KinkedInterestRateModel internal rateModel;

    MockERC20 internal usdc;
    MockERC20 internal weth;

    function setUp() public virtual {
        vm.startPrank(admin);

        registry = new ProtocolRegistry(admin);

        accessManager = AccessManager(_deployProxy(address(new AccessManager())));
        accessManager.initialize(address(registry), admin);

        bitScoreManager = BitScoreManager(_deployProxy(address(new BitScoreManager())));
        bitScoreManager.initialize(address(registry), admin);

        treasury = Treasury(_deployProxy(address(new Treasury())));
        treasury.initialize(address(registry), admin);

        poolManager = PoolManager(_deployProxy(address(new PoolManager())));
        poolManager.initialize(address(registry), admin);

        lendingManager = LendingManager(_deployProxy(address(new LendingManager())));
        lendingManager.initialize(address(registry), admin);

        vaultManager = VaultManager(_deployProxy(address(new VaultManager())));
        vaultManager.initialize(address(registry), admin);

        priceOracle = new StaticPriceOracle(admin);
        identityOracle = new MockIdentityOracle();

        registry.setAddress(registry.ACCESS_MANAGER(), address(accessManager));
        registry.setAddress(registry.BITSCORE_MANAGER(), address(bitScoreManager));
        registry.setAddress(registry.TREASURY(), address(treasury));
        registry.setAddress(registry.POOL_MANAGER(), address(poolManager));
        registry.setAddress(registry.LENDING_MANAGER(), address(lendingManager));
        registry.setAddress(registry.VAULT_MANAGER(), address(vaultManager));
        registry.setAddress(registry.PRICE_ORACLE(), address(priceOracle));
        registry.setAddress(registry.IDENTITY_ORACLE(), address(identityOracle));

        // Cross-module roles: LendingManager moves liquidity through
        // PoolManager; both managers report reputation events to
        // BitScoreManager; both collect fees into Treasury.
        poolManager.grantRole(poolManager.LENDING_MANAGER_ROLE(), address(lendingManager));
        treasury.grantRole(treasury.FEE_COLLECTOR_ROLE(), address(poolManager));
        treasury.grantRole(treasury.FEE_COLLECTOR_ROLE(), address(vaultManager));
        bitScoreManager.setReporterAuthorized(address(lendingManager), true);

        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        priceOracle.setPrice(address(usdc), 1e18); // $1.00
        priceOracle.setPrice(address(weth), 3000e18); // $3,000.00

        rateModel = new KinkedInterestRateModel({
            optimalUtilizationWad_: 0.8e18,
            baseRateRay_: 0.02e27, // 2% base APY
            slope1Ray_: 0.04e27, // +4% up to kink
            slope2Ray_: 0.75e27, // +75% beyond kink
            reserveFactorBps_: 1000 // 10%
        });

        poolManager.createPool(address(usdc), address(rateModel), 1000, 0, address(0));
        poolManager.createPool(address(weth), address(rateModel), 1000, 0, address(0));

        lendingManager.setBorrowConfig(
            address(usdc),
            DataTypes.BorrowConfig({
                isListed: true,
                borrowCap: 0,
                collateralFactorBps: 8000,
                liquidationThresholdBps: 8500,
                liquidationBonusBps: 500,
                closeFactorBps: 5000,
                isCollateralEligible: true
            })
        );
        lendingManager.setBorrowConfig(
            address(weth),
            DataTypes.BorrowConfig({
                isListed: true,
                borrowCap: 0,
                collateralFactorBps: 7500,
                liquidationThresholdBps: 8000,
                liquidationBonusBps: 750,
                closeFactorBps: 5000,
                isCollateralEligible: true
            })
        );

        // Bind every protocol capability to a Cleanverse Validator pool so
        // the identity-gating path is genuinely exercised by every test in
        // this suite by default, not left permanently open — tests that
        // specifically target the gate (e.g. an unverified borrower) then
        // only need to change identity STATE, not first go configure gating
        // that a real deployment would already have in place.
        accessManager.setCapabilityRequirement(IAccessManager.Capability.AccessLending, lendingPool);
        accessManager.setCapabilityRequirement(IAccessManager.Capability.AccessBorrowing, borrowingPool);
        accessManager.setCapabilityRequirement(IAccessManager.Capability.JoinLiquidityPools, poolsPool);
        accessManager.setCapabilityRequirement(IAccessManager.Capability.AccessYieldVaults, vaultsPool);

        vm.stopPrank();

        // Everyone is Cleanverse-verified and eligible for every capability
        // pool by default; individual tests override one or the other to
        // exercise the corresponding gating path.
        address[3] memory accounts = [alice, bob, liquidator];
        for (uint256 i = 0; i < accounts.length; i++) {
            identityOracle.setStatus(accounts[i], IIdentityOracle.IdentityStatus.Active);
            identityOracle.setPoolEligibility(lendingPool, accounts[i], true);
            identityOracle.setPoolEligibility(borrowingPool, accounts[i], true);
            identityOracle.setPoolEligibility(poolsPool, accounts[i], true);
            identityOracle.setPoolEligibility(vaultsPool, accounts[i], true);
        }

        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);
        usdc.mint(liquidator, 1_000_000e6);
        weth.mint(alice, 1_000e18);
        weth.mint(bob, 1_000e18);
    }

    function _deployProxy(address implementation) internal returns (address) {
        return address(new ERC1967Proxy(implementation, ""));
    }
}
