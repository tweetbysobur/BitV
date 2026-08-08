// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Errors
/// @notice Every custom error used across the BitV protocol, centralised.
/// @dev Centralising errors (rather than declaring them per-contract) means
///      the frontend's error-decoding layer maintains one ABI fragment
///      instead of six, and prevents the same failure condition from
///      silently drifting into two differently-named errors in two modules.
library Errors {
    // ── Access / roles ──────────────────────────────────────────────────
    error Unauthorized(address caller);
    error ZeroAddress();
    error InvalidRegistryKey(bytes32 key);

    // ── Cleanverse identity / compliance ────────────────────────────────
    /// @dev Thrown when a caller has no A-Pass record at all.
    error IdentityNotRegistered(address account);
    /// @dev Thrown when an A-Pass exists but is expired, frozen, or below
    ///      the tier/group/country requirements of the pool being accessed.
    error IdentityIneligible(address account, uint8 reasonCode);
    /// @dev The configured Cleanverse Validator pool has not been set for
    ///      this market — fails closed rather than skipping the check.
    error ValidatorPoolNotConfigured(address market);
    /// @dev The Cleanverse Validator pool reports itself paused.
    error ValidatorPoolPaused(address pool);

    // ── Market / pool state ─────────────────────────────────────────────
    error MarketNotFound(bytes32 marketId);
    error MarketAlreadyExists(bytes32 marketId);
    error MarketFrozen(bytes32 marketId);
    error MarketPaused(bytes32 marketId);
    error AssetNotSupported(address asset);
    error AssetAlreadyListed(address asset);

    // ── Amounts ──────────────────────────────────────────────────────────
    error ZeroAmount();
    error AmountExceedsBalance(uint256 requested, uint256 available);
    error AmountExceedsAvailableLiquidity(uint256 requested, uint256 available);
    error InsufficientShares(uint256 requested, uint256 available);

    // ── Lending / health ─────────────────────────────────────────────────
    error HealthFactorTooLow(uint256 healthFactorWad);
    error HealthFactorAboveLiquidationThreshold(uint256 healthFactorWad);
    error BorrowCapExceeded(bytes32 marketId, uint256 requested, uint256 cap);
    error CreditLineExceeded(address account, uint256 requested, uint256 limit);
    error CloseFactorExceeded(uint256 requested, uint256 maxRepayable);
    error NoOutstandingDebt(address account, bytes32 marketId);
    error CollateralRequired();

    // ── Vaults ───────────────────────────────────────────────────────────
    error VaultNotFound(bytes32 vaultId);
    error VaultCapExceeded(bytes32 vaultId, uint256 requested, uint256 cap);
    error WithdrawalLocked(bytes32 vaultId, uint64 unlockTimestamp);

    // ── Interest rate model ─────────────────────────────────────────────
    error InvalidRateModelParams();

    // ── Generic guards ───────────────────────────────────────────────────
    error ReentrantCall();
    error ContractPaused();
    error DeadlineExpired(uint256 deadline, uint256 nowTimestamp);
    error SlippageExceeded(uint256 minOut, uint256 actualOut);
    error InvalidBps(uint256 bps);
}
