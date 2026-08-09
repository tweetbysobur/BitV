// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BitVYieldVault} from "../src/core/BitVYieldVault.sol";
import {TestYieldStrategy} from "../src/vault/TestYieldStrategy.sol";

/**
 * @title DeployTestnetVault
 * @notice Deployment TEMPLATE for a testnet-only BitVYieldVault +
 * TestYieldStrategy pair — NOT executed by this milestone's automation
 * (run manually against Monad Testnet, per docs/testnet-smoke-test.md).
 *
 * Deploys, in order:
 *   1. BitVYieldVault, for the underlying asset given by VAULT_ASSET
 *      (expected: the already-deployed BitVTestToken, BVTEST) — wired
 *      to the same Cleanverse validator and AccessManager as the rest
 *      of the protocol.
 *   2. TestYieldStrategy bound to that vault — explicitly
 *      non-production (see its own NatSpec), requires the deployer to
 *      pass `confirmedTestOnlyDeployment = true`.
 *
 * Then sets the strategy as the vault's active strategy via
 * `setStrategy` (requires STRATEGY_MANAGER_ROLE, held by the deployer
 * per the TESTNET ADMIN MODEL — docs/admin-key-strategy.md).
 *
 * Does NOT allocate any funds to the strategy, set a vault cap, or set
 * a minimum deposit — those default to 0/uncapped and are configured
 * separately, deliberately, once the vault is live (see
 * docs/testnet-smoke-test.md for the exact sequence).
 *
 * Does NOT register the vault with Cleanverse — a fresh
 * BitVComplianceGuard-inheriting contract needs its own
 * POST /validator/register call (per docs/cleanverse-dependency-lock.md's
 * "Sandbox compliance registrations" pattern) before deposits will
 * pass compliance. That is a separate, off-chain step performed after
 * this script runs and its address is known.
 */
contract DeployTestnetVault is Script {
    function run() external {
        address deployer = msg.sender;

        address cleanverseValidator = vm.envAddress("CLEANVERSE_VALIDATOR_ADDRESS");
        require(cleanverseValidator != address(0), "CLEANVERSE_VALIDATOR_ADDRESS not set");

        address accessManager = vm.envAddress("ACCESS_MANAGER_ADDRESS");
        require(accessManager != address(0), "ACCESS_MANAGER_ADDRESS not set");

        address treasury = vm.envAddress("TREASURY_ADDRESS");
        require(treasury != address(0), "TREASURY_ADDRESS not set");

        address vaultAsset = vm.envAddress("VAULT_ASSET");
        require(vaultAsset != address(0), "VAULT_ASSET not set");

        string memory vaultName = vm.envOr("VAULT_NAME", string("BitV Test Vault"));
        string memory vaultSymbol = vm.envOr("VAULT_SYMBOL", string("bvtVAULT"));

        vm.startBroadcast();

        BitVYieldVault vault = new BitVYieldVault(
            IERC20(vaultAsset),
            vaultName,
            vaultSymbol,
            cleanverseValidator,
            deployer,
            accessManager,
            treasury,
            0, // vaultCap: 0 until VAULT_MANAGER_ROLE explicitly sets one
            0 // minDeposit: 0 until VAULT_MANAGER_ROLE explicitly sets one
        );

        TestYieldStrategy strategy = new TestYieldStrategy(vaultAsset, address(vault), true);

        vault.setStrategy(address(strategy));

        vm.stopBroadcast();

        console2.log("BitVYieldVault:", address(vault));
        console2.log("TestYieldStrategy:", address(strategy));
    }
}
