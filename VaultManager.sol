// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { BaseModule } from "./BaseModule.sol";
import { BitVReceiptToken } from "./BitVReceiptToken.sol";
import { IVaultManager } from "../interfaces/IVaultManager.sol";
import { IAccessManager } from "../interfaces/IAccessManager.sol";
import { IIdentityOracle } from "../interfaces/IIdentityOracle.sol";
import { ITreasury } from "../interfaces/ITreasury.sol";
import { DataTypes } from "../libraries/DataTypes.sol";
import { WadRayMath } from "../libraries/WadRayMath.sol";
import { PercentageMath } from "../libraries/PercentageMath.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title VaultManager
/// @notice Permissioned yield vaults. See `IVaultManager` for why this
///         wraps rather than implements ERC-4626.
/// @custom:storage-location erc7201:bitv.storage.VaultManager
contract VaultManager is BaseModule, IVaultManager {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    struct VaultManagerStorage {
        mapping(bytes32 vaultId => DataTypes.Vault) vaults;
        mapping(bytes32 vaultId => mapping(address account => uint40 timestamp)) lastDepositAt;
        uint256 vaultNonce;
    }

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("bitv.storage.VaultManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x678b8f19b066a74873618dfcf845ae2bf9144cfdeb378f7448e7060ab5aadd00;

    function _s() private pure returns (VaultManagerStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    modifier vaultExists(bytes32 vaultId) {
        if (_s().vaults[vaultId].asset == address(0)) revert Errors.VaultNotFound(vaultId);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address registry_, address admin) external initializer {
        __BaseModule_init(registry_, admin);
    }

    // ── Vault creation ───────────────────────────────────────────────────

    function createVault(
        address asset,
        uint16 minIdentityTier,
        address validatorPool,
        uint16 performanceFeeBps,
        uint128 depositCap,
        uint64 withdrawalLockSeconds,
        address strategyOrRewardsDistributor
    ) external onlyRole(GOVERNANCE_ROLE) returns (bytes32 vaultId, address shareToken) {
        if (asset == address(0) || strategyOrRewardsDistributor == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (performanceFeeBps > PercentageMath.BPS_DENOMINATOR) {
            revert Errors.InvalidBps(performanceFeeBps);
        }

        vaultId = keccak256(abi.encode(asset, _s().vaultNonce++));

        string memory symbol = IERC20Metadata(asset).symbol();
        BitVReceiptToken token = new BitVReceiptToken(
            address(this), asset, string.concat("BitV Vault ", symbol), string.concat("bvv", symbol)
        );
        shareToken = address(token);

        _s().vaults[vaultId] = DataTypes.Vault({
            asset: asset,
            shareToken: shareToken,
            totalAssets: 0,
            totalShares: 0,
            depositCap: depositCap,
            performanceFeeBps: performanceFeeBps,
            minIdentityTier: minIdentityTier,
            validatorPool: validatorPool,
            strategyOrRewardsDistributor: strategyOrRewardsDistributor,
            isPaused: false,
            withdrawalLockSeconds: withdrawalLockSeconds
        });

        emit VaultCreated(vaultId, asset, shareToken, minIdentityTier);
    }

    function setVaultState(bytes32 vaultId, bool isPaused)
        external
        onlyRole(GOVERNANCE_ROLE)
        vaultExists(vaultId)
    {
        _s().vaults[vaultId].isPaused = isPaused;
        emit VaultStateUpdated(vaultId, isPaused);
    }

    // ── Deposit / withdraw ───────────────────────────────────────────────

    function deposit(bytes32 vaultId, uint256 assets)
        external
        whenNotPaused
        nonReentrant
        vaultExists(vaultId)
        returns (uint256 shares)
    {
        if (assets == 0) revert Errors.ZeroAmount();

        DataTypes.Vault storage vault = _s().vaults[vaultId];
        if (vault.isPaused) revert Errors.MarketPaused(vaultId);

        _checkVaultAccess(vault, msg.sender);

        if (vault.depositCap != 0 && uint256(vault.totalAssets) + assets > vault.depositCap) {
            revert Errors.VaultCapExceeded(vaultId, uint256(vault.totalAssets) + assets, vault.depositCap);
        }

        shares = previewDeposit(vaultId, assets);

        vault.totalAssets += uint128(assets);
        vault.totalShares += uint128(shares);
        _s().lastDepositAt[vaultId][msg.sender] = uint40(block.timestamp);

        IERC20(vault.asset).safeTransferFrom(msg.sender, address(this), assets);
        BitVReceiptToken(vault.shareToken).mint(msg.sender, shares);

        emit VaultDeposited(vaultId, msg.sender, assets, shares);
    }

    function withdraw(bytes32 vaultId, uint256 shares)
        external
        whenNotPaused
        nonReentrant
        vaultExists(vaultId)
        returns (uint256 assets)
    {
        if (shares == 0) revert Errors.ZeroAmount();

        DataTypes.Vault storage vault = _s().vaults[vaultId];

        if (vault.withdrawalLockSeconds != 0) {
            uint64 unlockAt = _s().lastDepositAt[vaultId][msg.sender] + vault.withdrawalLockSeconds;
            if (block.timestamp < unlockAt) revert Errors.WithdrawalLocked(vaultId, unlockAt);
        }

        uint256 shareBalance = BitVReceiptToken(vault.shareToken).balanceOf(msg.sender);
        if (shares > shareBalance) revert Errors.InsufficientShares(shares, shareBalance);

        assets = previewWithdraw(vaultId, shares);

        vault.totalAssets -= uint128(assets);
        vault.totalShares -= uint128(shares);

        BitVReceiptToken(vault.shareToken).burn(msg.sender, shares);
        IERC20(vault.asset).safeTransfer(msg.sender, assets);

        emit VaultWithdrawn(vaultId, msg.sender, assets, shares);
    }

    // ── Rewards ──────────────────────────────────────────────────────────

    function distributeRewards(bytes32 vaultId, uint256 amount)
        external
        nonReentrant
        vaultExists(vaultId)
    {
        if (amount == 0) revert Errors.ZeroAmount();

        DataTypes.Vault storage vault = _s().vaults[vaultId];
        if (msg.sender != vault.strategyOrRewardsDistributor) revert Errors.Unauthorized(msg.sender);

        IERC20(vault.asset).safeTransferFrom(msg.sender, address(this), amount);

        uint256 fee = amount.percentMul(vault.performanceFeeBps);
        uint256 net = amount - fee;

        vault.totalAssets += uint128(net);

        if (fee > 0) {
            address treasury = registry().getAddress(registry().TREASURY());
            if (treasury != address(0)) {
                IERC20(vault.asset).forceApprove(treasury, fee);
                ITreasury(treasury).collectFee(vault.asset, fee);
            } else {
                // No treasury wired yet — credit the fee back to the vault
                // rather than stranding it unclaimed in this contract.
                vault.totalAssets += uint128(fee);
            }
        }

        emit RewardsDistributed(vaultId, amount, vault.totalAssets);
    }

    // ── Access gating ────────────────────────────────────────────────────

    function _checkVaultAccess(DataTypes.Vault storage vault, address account) internal view {
        IAccessManager(registry().requireAddress(registry().ACCESS_MANAGER())).requireCapability(
            IAccessManager.Capability.AccessYieldVaults, account
        );

        if (vault.minIdentityTier > 0 || vault.validatorPool != address(0)) {
            IIdentityOracle oracle =
                IIdentityOracle(registry().requireAddress(registry().IDENTITY_ORACLE()));

            if (vault.minIdentityTier > 0 && oracle.tierOf(account) < vault.minIdentityTier) {
                revert Errors.IdentityIneligible(account, uint8(oracle.statusOf(account)));
            }
            if (vault.validatorPool != address(0) && !oracle.isEligibleForPool(vault.validatorPool, account)) {
                revert Errors.IdentityIneligible(account, uint8(oracle.statusOf(account)));
            }
        }
    }

    // ── Views ────────────────────────────────────────────────────────────

    function getVault(bytes32 vaultId) external view returns (DataTypes.Vault memory) {
        return _s().vaults[vaultId];
    }

    function sharesOf(bytes32 vaultId, address account) external view returns (uint256) {
        return BitVReceiptToken(_s().vaults[vaultId].shareToken).balanceOf(account);
    }

    function previewDeposit(bytes32 vaultId, uint256 assets) public view returns (uint256) {
        DataTypes.Vault storage vault = _s().vaults[vaultId];
        if (vault.totalShares == 0) return assets;
        return (assets * vault.totalShares) / vault.totalAssets;
    }

    function previewWithdraw(bytes32 vaultId, uint256 shares) public view returns (uint256) {
        DataTypes.Vault storage vault = _s().vaults[vaultId];
        if (vault.totalShares == 0) return 0;
        return (shares * vault.totalAssets) / vault.totalShares;
    }

    function pricePerShare(bytes32 vaultId) external view returns (uint256) {
        DataTypes.Vault storage vault = _s().vaults[vaultId];
        if (vault.totalShares == 0) return WadRayMath.WAD;
        return uint256(vault.totalAssets).wadDiv(vault.totalShares);
    }
}
