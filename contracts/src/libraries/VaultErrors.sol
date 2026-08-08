// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Errors specific to BitVYieldVault / IBitVVaultStrategy —
/// distinct from ProtocolErrors (lending/pool) and ComplianceErrors
/// (Cleanverse), per the codebase's existing per-domain error library
/// convention.
library VaultErrors {
    error ZeroAddress();
    error ZeroAmount();
    error ZeroShares();
    error DepositsPaused();
    error WithdrawalsPaused();
    error StrategyOperationsPaused();
    error BelowMinimumDeposit(uint256 assets, uint256 minDeposit);
    error VaultCapExceeded(uint256 newTotal, uint256 cap);
    error OnlySelfService();
    error StrategyNotSet();
    error StrategyAssetMismatch();
    error StrategyVaultMismatch();
    error StrategyAllocationExceedsCap(uint256 newStrategyAssets, uint256 maxAllowed);
    error InsufficientLiquidity(uint256 requested, uint256 available);
    error InvalidBps(uint256 bps);
    error CallerNotVault();
    error NotTestOnlyDeployment();
}
