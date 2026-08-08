// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Script, console } from "forge-std/Script.sol";

import { StaticPriceOracle } from "../src/oracles/StaticPriceOracle.sol";

/// @title RefreshPrice
/// @notice Re-submits a price to `StaticPriceOracle` so it doesn't go stale.
///
/// @dev `StaticPriceOracle.MAX_STALENESS_SECONDS` is 1 hour by design (a
///      stale price silently accepted is more dangerous to a lending
///      protocol than an explicit "unavailable" revert — see the contract's
///      NatSpec). That's the correct behaviour for a protocol, but it means
///      ANY testnet session longer than an hour needs the price re-pushed,
///      or `getPriceUsd` starts reverting and every USD-denominated read in
///      the frontend (borrowing power, health factor) goes blank. This
///      script is that re-push, made a one-liner instead of a `cast send`
///      you'd otherwise have to reconstruct by hand each time.
///
///      Defaults to tUSDC at exactly $1.00 — override both via env if
///      you've listed a different test asset or want to simulate a price
///      move. Not a substitute for a real oracle; see `StaticPriceOracle`'s
///      contract-level NatSpec for the production migration path.
///
/// Usage:
///   forge script script/RefreshPrice.s.sol:RefreshPrice \
///     --rpc-url monad_testnet \
///     --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast
///
/// Required env:
///   BITV_PRICE_ORACLE_ADDRESS  — StaticPriceOracle address
///
/// Optional env (defaults to the tUSDC test market at $1.00):
///   REFRESH_ASSET_ADDRESS      — asset to re-price (default: tUSDC)
///   REFRESH_PRICE_USD_WAD      — WAD-scaled USD price (default: 1e18)
contract RefreshPrice is Script {
    address constant DEFAULT_TEST_ASSET = 0x4BB476d632EbF16a593dc8547754E4a4072f5df8; // tUSDC
    uint256 constant DEFAULT_PRICE_WAD = 1e18; // $1.00

    function run() external {
        address priceOracleAddr = vm.envAddress("BITV_PRICE_ORACLE_ADDRESS");
        address asset = vm.envOr("REFRESH_ASSET_ADDRESS", DEFAULT_TEST_ASSET);
        uint256 priceWad = vm.envOr("REFRESH_PRICE_USD_WAD", DEFAULT_PRICE_WAD);

        vm.startBroadcast();
        StaticPriceOracle(priceOracleAddr).setPrice(asset, priceWad);
        vm.stopBroadcast();

        console.log("Price refreshed.");
        console.log("  asset:      ", asset);
        console.log("  priceWad:   ", priceWad);
        console.log("  stale again in 1 hour (MAX_STALENESS_SECONDS)");
    }
}
