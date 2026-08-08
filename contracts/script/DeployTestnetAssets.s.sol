// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {BitVTestToken} from "../src/testing/BitVTestToken.sol";
import {StaticPriceOracle} from "../src/oracles/StaticPriceOracle.sol";
import {KinkedInterestRateModel} from "../src/oracles/KinkedInterestRateModel.sol";
import {BitVPoolManager} from "../src/core/BitVPoolManager.sol";

/**
 * @title DeployTestnetAssets
 * @notice Deployment TEMPLATE for BitV's Monad Testnet smoke-test asset
 * — NOT executed by this milestone. Deliberately separate from
 * `Deploy.s.sol` (which stays asset-agnostic, per its existing design
 * note that pool creation is a separate governance action) — this
 * script is the one place that decision is made concrete, for testnet
 * only.
 *
 * Deploys, in order:
 *   1. `StaticPriceOracle` — admin-set price source. NOT production-
 *      suitable (see its own NatSpec and docs/oracle-deployment-plan.md)
 *      — acceptable here only because this is an explicitly-labeled
 *      testnet deployment, not a real-value one.
 *   2. `BitVTestToken` — a plain, no-real-value ERC-20, deployed because
 *      no real, confirmed Monad Testnet asset address was available
 *      (docs/testnet-assets.md). Never a CVA; never presented as one.
 *   3. `KinkedInterestRateModel` — the existing deterministic rate
 *      model, with the documented suggested starting parameters from
 *      its own file (0% base, 4% at kink, 75% at 100% utilization,
 *      80% kink).
 *
 * Then, if `POOL_MANAGER_ADDRESS` is set (i.e. `Deploy.s.sol` has
 * already run and produced a real `BitVPoolManager`), creates a single
 * conservative pool for the test token — LTV 70%, liquidation threshold
 * 80%, liquidation bonus 5%, both borrowing and collateral enabled, no
 * caps set beyond a starting supply/borrow cap sized for smoke-testing
 * only.
 *
 * Every address consumed here is either freshly deployed by this
 * script or supplied via environment variable — nothing is guessed or
 * hardcoded.
 */
contract DeployTestnetAssets is Script {
    function run() external {
        address deployer = msg.sender;

        vm.startBroadcast();

        StaticPriceOracle oracle = new StaticPriceOracle(deployer);
        BitVTestToken testToken = new BitVTestToken("BitV Test Token", "BVTEST", 18, deployer, true);
        KinkedInterestRateModel rateModel = new KinkedInterestRateModel(
            deployer,
            0, // baseRateRay: 0%
            4e25, // slope1Ray: 4% at the kink
            75e25, // slope2Ray: 75% at 100% utilization
            80e25 // kinkRay: 80% utilization
        );

        // $1.00, 8 decimals — an arbitrary, clearly-labeled test price
        // for smoke-testing only, set by the deployer (StaticPriceOracle's
        // owner). Never presented as a real market price.
        oracle.setPrice(address(testToken), 1e8, 8);

        // Mint a smoke-test supply to the deployer, to fund test wallets
        // from. No real value regardless of amount.
        testToken.mint(deployer, 1_000_000e18);

        address poolManagerAddr = vm.envOr("POOL_MANAGER_ADDRESS", address(0));
        if (poolManagerAddr != address(0)) {
            BitVPoolManager poolManager = BitVPoolManager(poolManagerAddr);
            poolManager.createPool(
                address(testToken),
                BitVPoolManager.PoolConfigParams({
                    ltvBps: 7_000,
                    maxLtvWithScoreBps: 7_000, // no BitScore bonus configured for this smoke-test asset
                    liquidationThresholdBps: 8_000,
                    liquidationBonusBps: 500,
                    reserveFactorBps: 1_000,
                    supplyCap: 500_000e18,
                    borrowCap: 250_000e18,
                    interestRateModel: address(rateModel),
                    priceOracle: address(oracle),
                    isBorrowingEnabled: true,
                    isCollateralEnabled: true
                })
            );
            console2.log("Pool created for BitVTestToken on:", poolManagerAddr);
        } else {
            console2.log("POOL_MANAGER_ADDRESS not set - skipped pool creation.");
        }

        vm.stopBroadcast();

        console2.log("StaticPriceOracle:", address(oracle));
        console2.log("BitVTestToken:", address(testToken));
        console2.log("KinkedInterestRateModel:", address(rateModel));
    }
}
