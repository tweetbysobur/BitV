// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IInterestRateModel
/// @notice Pure function from a market's utilization to its current borrow
///         and supply rates.
/// @dev Pure and stateless by design: PoolManager owns all state (indices,
///      balances), the rate model owns none. This is what lets a market's
///      rate curve be swapped by governance (deploy a new model, point the
///      market at it) without migrating any accrued balances — the model
///      never held them.
interface IInterestRateModel {
    /// @param totalSupplied  Total underlying supplied to the market.
    /// @param totalBorrowed  Total underlying currently borrowed.
    /// @return borrowRateRay Annualized borrow rate, RAY-scaled.
    /// @return supplyRateRay Annualized supply rate, RAY-scaled.
    function getRates(uint256 totalSupplied, uint256 totalBorrowed)
        external
        view
        returns (uint256 borrowRateRay, uint256 supplyRateRay);

    /// @return Utilization = totalBorrowed / totalSupplied, WAD-scaled.
    ///         Returns 0 when totalSupplied is 0 (no supply means no
    ///         utilization, not divide-by-zero).
    function getUtilization(uint256 totalSupplied, uint256 totalBorrowed)
        external
        pure
        returns (uint256);
}
