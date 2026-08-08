// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Clean price-oracle boundary. BitV-original interface, not a
/// Cleanverse primitive. No production price source is wired up in this
/// milestone — see contracts/src/oracles/StaticPriceOracle.sol, which is
/// an admin-set placeholder explicitly not for production use.
interface IPriceOracle {
    /// @return price The asset's price in a shared unit across all
    /// assets an implementation prices (e.g. USD with `decimals`
    /// precision) — callers compare `price` values across assets
    /// directly, scaled by their respective `decimals`.
    /// @return decimals Precision of `price`.
    function getPrice(address asset) external view returns (uint256 price, uint8 decimals);
}
