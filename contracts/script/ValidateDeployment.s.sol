// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {BitVAccessManager} from "../src/core/BitVAccessManager.sol";
import {BitVTreasury} from "../src/core/BitVTreasury.sol";
import {BitVPoolManager} from "../src/core/BitVPoolManager.sol";
import {BitVLendingManager} from "../src/core/BitVLendingManager.sol";
import {BitScoreManager} from "../src/core/BitScoreManager.sol";
import {BitVRWACollateralRegistry} from "../src/core/BitVRWACollateralRegistry.sol";
import {BitVCVAAdapter} from "../src/core/BitVCVAAdapter.sol";

/**
 * @title ValidateDeployment
 * @notice Read-only post-deployment validation TEMPLATE — NOT executed
 * against any network by this milestone. Intended to be run (via `forge
 * script ... ` without `--broadcast`) after a real `Deploy.s.sol` run,
 * reading every deployed address from environment variables and failing
 * loudly (via `require`/revert) on the first thing that doesn't match
 * what deployment should have produced.
 *
 * This is deliberately conservative: it checks structural correctness
 * (code exists, references point where they should, roles are granted
 * where expected) — it does NOT and cannot validate off-chain facts
 * like "Cleanverse has actually registered this validator address" or
 * "this RWA asset is a real, Cleanverse-confirmed CVA."
 */
contract ValidateDeployment is Script {
    function run() external view {
        uint256 expectedChainId = vm.envUint("EXPECTED_CHAIN_ID"); // 10143 for Monad Testnet
        require(block.chainid == expectedChainId, "chain ID mismatch");

        address accessManagerAddr = vm.envAddress("ACCESS_MANAGER_ADDRESS");
        address treasuryAddr = vm.envAddress("TREASURY_ADDRESS");
        address poolManagerAddr = vm.envAddress("POOL_MANAGER_ADDRESS");
        address lendingManagerAddr = vm.envAddress("LENDING_MANAGER_ADDRESS");
        address bitScoreManagerAddr = vm.envAddress("BITSCORE_MANAGER_ADDRESS");
        address rwaRegistryAddr = vm.envAddress("RWA_REGISTRY_ADDRESS");
        address cvaAdapterAddr = vm.envAddress("CVA_ADAPTER_ADDRESS");
        address deployerAdmin = vm.envAddress("EXPECTED_ADMIN_ADDRESS");

        _requireNonZeroWithCode(accessManagerAddr, "BitVAccessManager");
        _requireNonZeroWithCode(treasuryAddr, "BitVTreasury");
        _requireNonZeroWithCode(poolManagerAddr, "BitVPoolManager");
        _requireNonZeroWithCode(lendingManagerAddr, "BitVLendingManager");
        _requireNonZeroWithCode(bitScoreManagerAddr, "BitScoreManager");
        _requireNonZeroWithCode(rwaRegistryAddr, "BitVRWACollateralRegistry");
        _requireNonZeroWithCode(cvaAdapterAddr, "BitVCVAAdapter");

        BitVAccessManager accessManager = BitVAccessManager(accessManagerAddr);
        BitVPoolManager poolManager = BitVPoolManager(poolManagerAddr);
        BitVLendingManager lendingManager = BitVLendingManager(lendingManagerAddr);
        BitScoreManager bitScoreManager = BitScoreManager(bitScoreManagerAddr);
        BitVRWACollateralRegistry rwaRegistry = BitVRWACollateralRegistry(rwaRegistryAddr);
        BitVCVAAdapter cvaAdapter = BitVCVAAdapter(cvaAdapterAddr);
        (cvaAdapter); // referenced for completeness; no further on-chain state to check yet

        // ── Role assignments ─────────────────────────────────────────
        require(accessManager.hasRole(accessManager.DEFAULT_ADMIN_ROLE(), deployerAdmin), "admin missing DEFAULT_ADMIN_ROLE");
        require(accessManager.hasRole(accessManager.PROTOCOL_ADMIN_ROLE(), deployerAdmin), "admin missing PROTOCOL_ADMIN_ROLE");
        require(accessManager.hasRole(accessManager.RISK_MANAGER_ROLE(), deployerAdmin), "admin missing RISK_MANAGER_ROLE");
        require(accessManager.hasRole(accessManager.PAUSER_ROLE(), deployerAdmin), "admin missing PAUSER_ROLE");
        require(accessManager.hasRole(accessManager.RWA_ADMIN_ROLE(), deployerAdmin), "admin missing RWA_ADMIN_ROLE");

        // ── Cross-contract references ────────────────────────────────
        require(poolManager.lendingManager() == lendingManagerAddr, "PoolManager.lendingManager mismatch");
        require(address(lendingManager.POOL_MANAGER()) == poolManagerAddr, "LendingManager.POOL_MANAGER mismatch");
        require(address(lendingManager.bitScoreManager()) == bitScoreManagerAddr, "LendingManager.bitScoreManager mismatch");
        require(address(lendingManager.rwaRegistry()) == rwaRegistryAddr, "LendingManager.rwaRegistry mismatch");
        require(bitScoreManager.lendingManager() == lendingManagerAddr, "BitScoreManager.lendingManager mismatch");
        require(address(rwaRegistry.POOL_MANAGER()) == poolManagerAddr, "RWARegistry.POOL_MANAGER mismatch");
        require(address(rwaRegistry.cvaAdapter()) == cvaAdapterAddr, "RWARegistry.cvaAdapter mismatch");

        // ── Treasury wiring ───────────────────────────────────────────
        require(poolManager.TREASURY() == treasuryAddr, "PoolManager.TREASURY mismatch");
        require(lendingManager.TREASURY() == treasuryAddr, "LendingManager.TREASURY mismatch");

        // ── BitScore scale sanity (this milestone's 0-100 rescale) ────
        require(bitScoreManager.MAX_SCORE() == 100, "BitScoreManager.MAX_SCORE is not 100 (legacy scale?)");

        // ── Compliance (CVI) configuration (Build 10 Phase 10) ────────
        // Every BitVComplianceGuard-inheriting contract must be wired to
        // the SAME Cleanverse validator — a mismatch here would mean
        // compliance is being checked against two different sources of
        // truth for the same protocol, which must never happen silently.
        address expectedValidator = vm.envAddress("CLEANVERSE_VALIDATOR_ADDRESS");
        _requireNonZeroWithCode(expectedValidator, "Cleanverse CVI validator");
        require(
            address(poolManager.COMPLIANCE_VALIDATOR()) == expectedValidator,
            "PoolManager.COMPLIANCE_VALIDATOR mismatch"
        );
        require(
            address(lendingManager.COMPLIANCE_VALIDATOR()) == expectedValidator,
            "LendingManager.COMPLIANCE_VALIDATOR mismatch"
        );

        // ── Pool / lending / vault / RWA per-asset configuration ───────
        // Deliberately NOT checked here: no pool, RWA asset, or vault
        // exists immediately after core deployment (pool creation, RWA
        // registration, and vault deployment are separate, asset-specific
        // governance actions — see docs/deployment-readiness.md's
        // "Post-deployment configuration" section). A per-asset
        // validation pass belongs in a separate script run once specific
        // assets are configured, not fabricated here against nothing.

        console2.log("Validation passed.");
    }

    function _requireNonZeroWithCode(address addr, string memory label) internal view {
        require(addr != address(0), string.concat(label, ": zero address"));
        require(addr.code.length > 0, string.concat(label, ": no code at address"));
    }
}
