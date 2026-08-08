// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script, console } from "forge-std/Script.sol";

import { PoolManager } from "../src/core/PoolManager.sol";
import { LendingManager } from "../src/core/LendingManager.sol";
import { StaticPriceOracle } from "../src/oracles/StaticPriceOracle.sol";
import { KinkedInterestRateModel } from "../src/oracles/KinkedInterestRateModel.sol";
import { DataTypes } from "../src/libraries/DataTypes.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";

/// @title CreateTestMarket
/// @notice Testnet-only helper: deploys a mock USDC-like token, mints a
///         supply to the deployer, lists it as an open (ungated) BitV
///         market, sets a static USD price, and enables it as collateral.
///
/// @dev `MockERC20` lives in `test/mocks/` deliberately — it is not part of
///      the protocol's production contract surface, and importing a test
///      helper from a deployment script is exactly the signal that this
///      script itself is for testnet bring-up, not a template for listing a
///      real asset. Listing a REAL market means pointing `createPool` at an
///      already-deployed token (real USDC, a Cleanverse A-Token, etc.) —
///      this script exists only to give a fresh testnet deployment something
///      to actually lend, borrow, and supply against.
///
/// Usage:
///   forge script script/CreateTestMarket.s.sol:CreateTestMarket \
///     --rpc-url monad_testnet \
///     --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast
contract CreateTestMarket is Script {
    // Two-slope rate curve: gentle below 80% utilization, steep above it.
    uint256 constant OPTIMAL_UTILIZATION_WAD = 0.8e18;
    uint256 constant BASE_RATE_RAY = 0.02e27; // 2% APY at 0% utilization
    uint256 constant SLOPE1_RAY = 0.04e27; // +4% APY across 0% -> 80% utilization
    uint256 constant SLOPE2_RAY = 0.75e27; // +75% APY across 80% -> 100% utilization
    uint16 constant RESERVE_FACTOR_BPS = 1_000; // 10% of borrower interest to Treasury

    uint256 constant MINT_AMOUNT = 1_000_000e6; // 1,000,000 tUSDC to the deployer

    function run() external {
        address poolManagerAddr = vm.envAddress("BITV_POOL_MANAGER_ADDRESS");
        address lendingManagerAddr = vm.envAddress("BITV_LENDING_MANAGER_ADDRESS");
        address priceOracleAddr = vm.envAddress("BITV_PRICE_ORACLE_ADDRESS");
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        vm.startBroadcast();

        // ── Test asset ───────────────────────────────────────────────────
        MockERC20 token = new MockERC20("Test USD Coin", "tUSDC", 6);
        token.mint(deployer, MINT_AMOUNT);
        console.log("tUSDC:", address(token));

        // ── Rate model (one per market, stateless — see contract NatSpec) ──
        KinkedInterestRateModel rateModel = new KinkedInterestRateModel(
            OPTIMAL_UTILIZATION_WAD, BASE_RATE_RAY, SLOPE1_RAY, SLOPE2_RAY, RESERVE_FACTOR_BPS
        );
        console.log("KinkedInterestRateModel:", address(rateModel));

        // ── List the pool — open market, no Validator pool gate ─────────
        PoolManager poolManager = PoolManager(poolManagerAddr);
        address aToken = poolManager.createPool({
            asset: address(token),
            rateModel: address(rateModel),
            reserveFactorBps: RESERVE_FACTOR_BPS,
            supplyCap: 0, // unlimited
            validatorPool: address(0) // open — no Cleanverse gate on this test market
        });
        console.log("bvtUSDC (aToken):", aToken);

        // ── Price: $1.00, matching a stablecoin ──────────────────────────
        StaticPriceOracle(priceOracleAddr).setPrice(address(token), 1e18);

        // ── Enable borrowing + collateral use ────────────────────────────
        LendingManager(lendingManagerAddr).setBorrowConfig(
            address(token),
            DataTypes.BorrowConfig({
                isListed: true,
                borrowCap: 0, // unlimited
                collateralFactorBps: 8_000, // 80% max LTV
                liquidationThresholdBps: 8_500, // 85% liquidation threshold
                liquidationBonusBps: 500, // 5% liquidation bonus
                closeFactorBps: 5_000, // up to 50% of debt repayable per liquidation
                isCollateralEligible: true
            })
        );

        vm.stopBroadcast();

        console.log("");
        console.log("Market created. Add to frontend .env.local:");
        console.log("NEXT_PUBLIC_BITV_MARKET_ASSETS=\"tUSDC:%s:6\"", address(token));
        console.log("");
        console.log("StaticPriceOracle prices go stale after 1 hour (MAX_STALENESS_SECONDS).");
        console.log("Re-run setPrice periodically or the market will show 'unavailable' pricing.");
    }
}
