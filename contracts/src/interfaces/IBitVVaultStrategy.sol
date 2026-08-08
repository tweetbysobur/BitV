// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IBitVVaultStrategy
 * @notice Boundary between BitVYieldVault (accounting, compliance,
 * limits, pause, fees) and a strategy contract (yield execution,
 * asset-specific deployment). Per docs/yield-vault-specification.md §3,
 * §6: the vault owns every accounting decision; the strategy only ever
 * moves its own already-received assets and reports what it holds. A
 * strategy MUST NOT be able to mint/burn vault shares, change vault
 * configuration, or otherwise influence vault accounting beyond the
 * plain asset amounts it reports via `totalAssets()`.
 *
 * A strategy trusts exactly one caller (the vault that deployed it,
 * analogous to BitVPoolManager's `onlyLendingManager` single-trusted-
 * caller pattern) and reverts for anyone else.
 */
interface IBitVVaultStrategy {
    /// @notice The single underlying ERC-20 this strategy accepts —
    /// must match the owning vault's `asset()`.
    function asset() external view returns (address);

    /// @notice The vault this strategy is bound to and trusts.
    function vault() external view returns (address);

    /// @notice Total underlying-asset value this strategy currently
    /// holds/controls, as best the strategy can report it. Called by
    /// the vault to compute `totalAssets()`.
    function totalAssets() external view returns (uint256);

    /// @notice Pull `amount` of the underlying asset from the vault
    /// (via prior approval) and deploy it. Callable only by `vault()`.
    function deposit(uint256 amount) external;

    /// @notice Recover `amount` of the underlying asset and transfer it
    /// back to the vault. Callable only by `vault()`. Must revert if
    /// `amount` exceeds what the strategy can actually return under
    /// normal operation (use `emergencyWithdraw` for a best-effort,
    /// non-reverting recovery instead).
    function withdraw(uint256 amount) external;

    /// @notice Best-effort recovery of everything the strategy can
    /// return right now, even at a loss relative to what was deployed.
    /// Must not revert solely because the strategy is impaired — that
    /// is exactly the condition this function exists to handle. Returns
    /// the amount actually transferred back to the vault. Callable only
    /// by `vault()`.
    function emergencyWithdraw() external returns (uint256 recovered);
}
