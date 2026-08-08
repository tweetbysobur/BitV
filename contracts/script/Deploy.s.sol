// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BitVAccessManager} from "../src/core/BitVAccessManager.sol";
import {BitVTreasury} from "../src/core/BitVTreasury.sol";
import {BitVPoolManager} from "../src/core/BitVPoolManager.sol";
import {BitVLendingManager} from "../src/core/BitVLendingManager.sol";
import {BitScoreManager} from "../src/core/BitScoreManager.sol";
import {BitVRWACollateralRegistry} from "../src/core/BitVRWACollateralRegistry.sol";
import {BitVCVAAdapter} from "../src/core/BitVCVAAdapter.sol";
import {BitVYieldVault} from "../src/core/BitVYieldVault.sol";

/**
 * @title Deploy
 * @notice Deployment orchestration TEMPLATE — NOT executed, NOT run
 * against any network by this milestone (Build 09, deployment-readiness
 * audit only). See docs/deployment-readiness.md for the full audit this
 * script's structure is based on.
 *
 * Deploys, in dependency order, every BitV contract that does NOT
 * require a per-asset deployment decision (pools, RWA asset
 * registration, a yield vault's underlying asset, and any strategy are
 * all asset-specific governance actions taken *after* this script, not
 * part of it — matching the original template's existing note that pool
 * creation is deliberately out of scope here).
 *
 * BLOCKED as of this milestone: every contract that inherits
 * BitVComplianceGuard (BitVPoolManager, BitVLendingManager,
 * BitVYieldVault) requires `CLEANVERSE_VALIDATOR_ADDRESS` — Cleanverse
 * has not confirmed a validator address, or even Monad Testnet support
 * itself, for any network (docs/cleanverse-integration.md's "Deployment
 * Readiness" section, docs/deployment-readiness.md). This script
 * deliberately has no fallback/default and reverts if that env var is
 * unset or zero rather than silently deploying against nothing — do not
 * remove that check to "unblock" a run.
 *
 * A BitVYieldVault is deployed here only if `YIELD_VAULT_ASSET` is set,
 * since it requires a real underlying ERC-20 — leave it unset to skip.
 *
 * Do not run this until every item in docs/deployment-readiness.md's
 * table is READY.
 */
contract Deploy is Script {
    function run() external {
        address cleanverseValidator = vm.envAddress("CLEANVERSE_VALIDATOR_ADDRESS");
        require(cleanverseValidator != address(0), "CLEANVERSE_VALIDATOR_ADDRESS not set");

        address deployer = msg.sender;

        vm.startBroadcast();

        // ── Layer 0: no dependencies ────────────────────────────────────
        BitVAccessManager accessManager = new BitVAccessManager(deployer);

        // ── Layer 1: depends only on accessManager ──────────────────────
        BitVTreasury treasury = new BitVTreasury(address(accessManager));
        BitScoreManager bitScoreManager = new BitScoreManager(address(accessManager));

        // ── Layer 2: depends on accessManager + cleanverseValidator ─────
        BitVPoolManager poolManager =
            new BitVPoolManager(cleanverseValidator, deployer, address(accessManager), address(treasury));

        // ── Layer 3: depends on poolManager ─────────────────────────────
        BitVLendingManager lendingManager = new BitVLendingManager(
            cleanverseValidator, deployer, address(accessManager), address(poolManager), address(treasury)
        );
        BitVRWACollateralRegistry rwaRegistry =
            new BitVRWACollateralRegistry(address(accessManager), address(poolManager));

        // ── Layer 4: no on-chain contract dependency, admin-configured later ─
        BitVCVAAdapter cvaAdapter = new BitVCVAAdapter(address(accessManager));

        // ── Post-deployment wiring (on-chain configuration) ─────────────
        poolManager.setLendingManager(address(lendingManager));
        lendingManager.setBitScoreManager(address(bitScoreManager));
        lendingManager.setRwaRegistry(address(rwaRegistry));
        bitScoreManager.setLendingManager(address(lendingManager));
        rwaRegistry.setCVAAdapter(address(cvaAdapter));

        // ── Optional: a single BitVYieldVault, only if an underlying
        // asset is explicitly configured. Vault-specific parameters
        // (cap, min deposit) default conservatively (0 cap = no
        // deposits accepted, 0 min deposit) and MUST be set explicitly
        // by VAULT_MANAGER_ROLE post-deployment before real use.
        address yieldVaultAsset = vm.envOr("YIELD_VAULT_ASSET", address(0));
        if (yieldVaultAsset != address(0)) {
            string memory vaultName = vm.envOr("YIELD_VAULT_NAME", string("BitV Yield Vault"));
            string memory vaultSymbol = vm.envOr("YIELD_VAULT_SYMBOL", string("bvYIELD"));
            BitVYieldVault vault = new BitVYieldVault(
                IERC20(yieldVaultAsset),
                vaultName,
                vaultSymbol,
                cleanverseValidator,
                deployer,
                address(accessManager),
                address(treasury),
                0, // vaultCap: 0 until VAULT_MANAGER_ROLE explicitly sets one
                0 // minDeposit: 0 until VAULT_MANAGER_ROLE explicitly sets one
            );
            console2.log("BitVYieldVault:", address(vault));
        }

        vm.stopBroadcast();

        console2.log("BitVAccessManager:", address(accessManager));
        console2.log("BitVTreasury:", address(treasury));
        console2.log("BitScoreManager:", address(bitScoreManager));
        console2.log("BitVPoolManager:", address(poolManager));
        console2.log("BitVLendingManager:", address(lendingManager));
        console2.log("BitVRWACollateralRegistry:", address(rwaRegistry));
        console2.log("BitVCVAAdapter:", address(cvaAdapter));

        // Note: no pools are created, no RWA assets are registered, no
        // CVA policy contracts are wired, and no oracle/interest-rate-
        // model is deployed here — these are all separate, deliberate
        // per-asset governance actions taken after this script, not
        // part of initial protocol deployment. See
        // docs/deployment-readiness.md's "Post-deployment configuration"
        // section for the full checklist.
    }
}
