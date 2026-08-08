// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { DataTypes } from "../libraries/DataTypes.sol";

/// @title IVaultManager
/// @notice Permissioned yield vaults. Share accounting follows the ERC-4626
///         convention (deposit assets, receive shares; redeem shares, receive
///         assets, share price = totalAssets/totalShares) without inheriting
///         the ERC-4626 interface directly — vault ELIGIBILITY is gated by
///         Cleanverse identity tier and, optionally, a Validator pool, which
///         ERC-4626's standard `deposit`/`mint` entry points have no room to
///         express or revert distinctly on. Wrapping rather than
///         implementing ERC-4626 keeps that gating explicit in the interface
///         instead of buried behind a spec-compliant signature that silently
///         reverts for reasons a generic ERC-4626 integrator wouldn't expect.
interface IVaultManager {
    event VaultCreated(
        bytes32 indexed vaultId, address indexed asset, address shareToken, uint16 minIdentityTier
    );
    event VaultDeposited(bytes32 indexed vaultId, address indexed account, uint256 assets, uint256 shares);
    event VaultWithdrawn(bytes32 indexed vaultId, address indexed account, uint256 assets, uint256 shares);
    event RewardsDistributed(bytes32 indexed vaultId, uint256 amount, uint256 newTotalAssets);
    event VaultStateUpdated(bytes32 indexed vaultId, bool isPaused);

    function createVault(
        address asset,
        uint16 minIdentityTier,
        address validatorPool,
        uint16 performanceFeeBps,
        uint128 depositCap,
        uint64 withdrawalLockSeconds,
        address strategyOrRewardsDistributor
    ) external returns (bytes32 vaultId, address shareToken);

    function deposit(bytes32 vaultId, uint256 assets) external returns (uint256 shares);
    function withdraw(bytes32 vaultId, uint256 shares) external returns (uint256 assets);

    /// @notice Restricted to the vault's configured
    ///         `strategyOrRewardsDistributor`. Increases `totalAssets`
    ///         without minting shares — the mechanism by which per-share
    ///         value (and therefore yield) increases, net of
    ///         `performanceFeeBps` routed to Treasury.
    function distributeRewards(bytes32 vaultId, uint256 amount) external;

    function getVault(bytes32 vaultId) external view returns (DataTypes.Vault memory);
    function sharesOf(bytes32 vaultId, address account) external view returns (uint256);
    function previewDeposit(bytes32 vaultId, uint256 assets) external view returns (uint256 shares);
    function previewWithdraw(bytes32 vaultId, uint256 shares) external view returns (uint256 assets);
    function pricePerShare(bytes32 vaultId) external view returns (uint256 wad);

    function setVaultState(bytes32 vaultId, bool isPaused) external;
}
