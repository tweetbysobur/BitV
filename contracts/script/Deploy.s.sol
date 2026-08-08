// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {BitVAccessManager} from "../src/core/BitVAccessManager.sol";
import {BitVTreasury} from "../src/core/BitVTreasury.sol";
import {BitVPoolManager} from "../src/core/BitVPoolManager.sol";
import {BitVLendingManager} from "../src/core/BitVLendingManager.sol";

/**
 * @title Deploy
 * @notice Deployment configuration TEMPLATE — NOT executed, NOT run
 * against any network by this milestone. Exists so the Cleanverse
 * validator address stays external, deployment-time configuration
 * (per Build 03's explicit constraint: "Do not hardcode a Cleanverse
 * address... The validator address must remain deployment-time
 * configuration") rather than something baked into contract source.
 *
 * `CLEANVERSE_VALIDATOR_ADDRESS` MUST be supplied via environment
 * variable at deploy time, once Cleanverse confirms its address on
 * whichever network is actually being deployed to — this script
 * deliberately has no fallback/default value and reverts if it's unset
 * or zero, rather than silently deploying against nothing.
 *
 * Do not run this until:
 *   1. Cleanverse confirms explicit Monad Testnet support (or whichever
 *      network is being targeted) — see docs/cleanverse-integration.md's
 *      "Deployment Readiness" section, still UNCONFIRMED as of this
 *      milestone.
 *   2. `CLEANVERSE_VALIDATOR_ADDRESS` is a real, Cleanverse-confirmed
 *      address for that network.
 *   3. This script itself has been reviewed alongside real deployment
 *      requirements (e.g. multisig ownership rather than a single EOA
 *      admin, discussed but not decided in docs/protocol-architecture.md).
 */
contract Deploy is Script {
    function run() external {
        address cleanverseValidator = vm.envAddress("CLEANVERSE_VALIDATOR_ADDRESS");
        require(cleanverseValidator != address(0), "CLEANVERSE_VALIDATOR_ADDRESS not set");

        address deployer = msg.sender;

        vm.startBroadcast();

        BitVAccessManager accessManager = new BitVAccessManager(deployer);
        BitVTreasury treasury = new BitVTreasury(address(accessManager));
        BitVPoolManager poolManager =
            new BitVPoolManager(cleanverseValidator, deployer, address(accessManager), address(treasury));
        BitVLendingManager lendingManager = new BitVLendingManager(
            cleanverseValidator, deployer, address(accessManager), address(poolManager), address(treasury)
        );

        poolManager.setLendingManager(address(lendingManager));

        vm.stopBroadcast();

        // Note: no pools are created here — pool creation (asset,
        // risk params, oracle, interest rate model) is a separate,
        // deliberate governance action, not part of initial deployment.
    }
}
