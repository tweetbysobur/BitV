// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script, console } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { ProtocolRegistry } from "../src/core/ProtocolRegistry.sol";
import { AccessManager } from "../src/core/AccessManager.sol";
import { BitScoreManager } from "../src/core/BitScoreManager.sol";
import { Treasury } from "../src/core/Treasury.sol";
import { PoolManager } from "../src/core/PoolManager.sol";
import { LendingManager } from "../src/core/LendingManager.sol";
import { VaultManager } from "../src/core/VaultManager.sol";
import { CleanverseIdentityAdapter } from "../src/core/CleanverseIdentityAdapter.sol";
import { StaticPriceOracle } from "../src/oracles/StaticPriceOracle.sol";

/// @title Deploy
/// @notice Deploys and wires the complete BitV protocol suite in the order
///         required by its dependency graph. See
///         `docs/contracts-architecture.md` §Deployment order for why each
///         step must precede the next — this script is that ordering made
///         executable, not an independent derivation of it.
///
/// Usage:
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url monad_testnet \
///     --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast --verify
///
/// Required environment variables (see `.env.example` in this directory):
///   DEPLOYER_ADDRESS               — becomes DEFAULT_ADMIN_ROLE / GOVERNANCE_ROLE
///   CLEANVERSE_APASS_ADDRESS       — 0x0 permitted; adapter degrades to Unregistered-for-everyone
///   CLEANVERSE_VALIDATOR_ADDRESS   — 0x0 permitted; pool checks revert ValidatorPoolNotConfigured
contract Deploy is Script {
    struct Deployment {
        ProtocolRegistry registry;
        AccessManager accessManager;
        BitScoreManager bitScoreManager;
        Treasury treasury;
        PoolManager poolManager;
        LendingManager lendingManager;
        VaultManager vaultManager;
        CleanverseIdentityAdapter identityAdapter;
        StaticPriceOracle priceOracle;
    }

    function run() external returns (Deployment memory d) {
        address admin = vm.envAddress("DEPLOYER_ADDRESS");
        address aPassAddress = vm.envOr("CLEANVERSE_APASS_ADDRESS", address(0));
        address validatorAddress = vm.envOr("CLEANVERSE_VALIDATOR_ADDRESS", address(0));

        vm.startBroadcast();

        // ── Step 1: Registry — must exist before anything that resolves
        // peers through it, i.e. everything else. ────────────────────────
        d.registry = new ProtocolRegistry(admin);
        console.log("ProtocolRegistry:", address(d.registry));

        // ── Step 2: Standalone infrastructure with no dependency on the
        // registry's CONTENTS yet (only need the registry's address to point
        // proxies at, and to self-register into once deployed). ──────────
        d.identityAdapter = new CleanverseIdentityAdapter(admin, aPassAddress, validatorAddress);
        console.log("CleanverseIdentityAdapter:", address(d.identityAdapter));

        d.priceOracle = new StaticPriceOracle(admin);
        console.log("StaticPriceOracle:", address(d.priceOracle));

        // ── Step 3: Upgradeable managers, deployed behind ERC1967 proxies.
        // Order among these five does not matter to each OTHER at
        // construction time (none call into a peer during `initialize`) —
        // it matters only that the registry entries below are all set
        // before any USER-FACING call that resolves a peer happens. ──────
        d.accessManager = AccessManager(_deployProxy(address(new AccessManager())));
        d.accessManager.initialize(address(d.registry), admin);
        console.log("AccessManager:", address(d.accessManager));

        d.bitScoreManager = BitScoreManager(_deployProxy(address(new BitScoreManager())));
        d.bitScoreManager.initialize(address(d.registry), admin);
        console.log("BitScoreManager:", address(d.bitScoreManager));

        d.treasury = Treasury(_deployProxy(address(new Treasury())));
        d.treasury.initialize(address(d.registry), admin);
        console.log("Treasury:", address(d.treasury));

        d.poolManager = PoolManager(_deployProxy(address(new PoolManager())));
        d.poolManager.initialize(address(d.registry), admin);
        console.log("PoolManager:", address(d.poolManager));

        d.lendingManager = LendingManager(_deployProxy(address(new LendingManager())));
        d.lendingManager.initialize(address(d.registry), admin);
        console.log("LendingManager:", address(d.lendingManager));

        d.vaultManager = VaultManager(_deployProxy(address(new VaultManager())));
        d.vaultManager.initialize(address(d.registry), admin);
        console.log("VaultManager:", address(d.vaultManager));

        // ── Step 4: Register every module's address. Every manager's
        // `registry()` lookups (e.g. AccessManager resolving
        // IDENTITY_ORACLE, PoolManager resolving TREASURY) start working
        // only after this step — nothing above depends on it having
        // happened yet, which is exactly why it is safe to do last. ──────
        d.registry.setAddress(d.registry.ACCESS_MANAGER(), address(d.accessManager));
        d.registry.setAddress(d.registry.BITSCORE_MANAGER(), address(d.bitScoreManager));
        d.registry.setAddress(d.registry.TREASURY(), address(d.treasury));
        d.registry.setAddress(d.registry.POOL_MANAGER(), address(d.poolManager));
        d.registry.setAddress(d.registry.LENDING_MANAGER(), address(d.lendingManager));
        d.registry.setAddress(d.registry.VAULT_MANAGER(), address(d.vaultManager));
        d.registry.setAddress(d.registry.IDENTITY_ORACLE(), address(d.identityAdapter));
        d.registry.setAddress(d.registry.PRICE_ORACLE(), address(d.priceOracle));

        // ── Step 5: Cross-module roles. These are AccessControl grants on
        // specific manager instances (not registry entries), and must run
        // after those managers exist. `LENDING_MANAGER_ROLE` on PoolManager
        // is what lets LendingManager call `borrowFromPool` /
        // `notifyRepay` / `notifyDebtAccrued`; `FEE_COLLECTOR_ROLE` on
        // Treasury is what lets PoolManager and VaultManager route fees. ──
        d.poolManager.grantRole(d.poolManager.LENDING_MANAGER_ROLE(), address(d.lendingManager));
        d.treasury.grantRole(d.treasury.FEE_COLLECTOR_ROLE(), address(d.poolManager));
        d.treasury.grantRole(d.treasury.FEE_COLLECTOR_ROLE(), address(d.vaultManager));
        d.bitScoreManager.setReporterAuthorized(address(d.lendingManager), true);

        vm.stopBroadcast();

        console.log("---");
        console.log("Deployment complete. Next steps:");
        console.log("1. Confirm CLEANVERSE_APASS_ADDRESS / CLEANVERSE_VALIDATOR_ADDRESS");
        console.log("   against Cleanverse's actual deployed contracts (see");
        console.log("   ICleanverseAPass.sol / ICleanverseValidator.sol provenance notes)");
        console.log("   before relying on identity gating in production.");
        console.log("2. Call PoolManager.createPool / LendingManager.setBorrowConfig /");
        console.log("   VaultManager.createVault per listed market via a separate");
        console.log("   governance script (deliberately NOT bundled into this deploy");
        console.log("   script, since market parameters are a governance decision,");
        console.log("   not a deployment constant).");
        console.log("3. Call AccessManager.setCapabilityRequirement for each");
        console.log("   Capability once the corresponding Cleanverse Validator pools");
        console.log("   are registered.");
    }

    function _deployProxy(address implementation) internal returns (address) {
        return address(new ERC1967Proxy(implementation, ""));
    }
}
