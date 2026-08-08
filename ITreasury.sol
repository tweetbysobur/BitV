// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ITreasury
/// @notice Protocol fee sink and reserve manager. Every module that collects
///         a fee (PoolManager's reserve factor, LendingManager's liquidation
///         spread, VaultManager's performance fee) routes it here rather
///         than to an arbitrary or per-module-configured address — one
///         auditable destination for protocol revenue, and one place
///         governance later points at a DAO treasury or fee-distribution
///         contract without touching the modules that generate the fees.
interface ITreasury {
    event FeeCollected(address indexed asset, address indexed source, uint256 amount);
    event LiquidationProceedsReceived(address indexed asset, uint256 amount);
    event ReserveWithdrawn(address indexed asset, address indexed to, uint256 amount, address indexed sender);

    /// @notice Pulls `amount` of `asset` from `msg.sender` (a protocol
    ///         module with prior approval) into the treasury's reserves.
    function collectFee(address asset, uint256 amount) external;

    /// @notice Records liquidation-proceeds income for accounting/event
    ///         purposes when a module has already transferred the asset in
    ///         directly (avoids a redundant approve+transferFrom round trip
    ///         on the liquidation hot path).
    function notifyLiquidationProceeds(address asset, uint256 amount) external;

    /// @notice Governance-only. Withdraws from reserves — the sole
    ///         value-extraction path out of the treasury, gated behind
    ///         `TREASURER_ROLE` and, per the pausable emergency controls
    ///         shared across the protocol, blockable in an incident.
    function withdrawReserve(address asset, address to, uint256 amount) external;

    function reserveBalance(address asset) external view returns (uint256);
}
