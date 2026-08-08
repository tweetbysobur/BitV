// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {BitVComplianceGuard} from "../compliance/BitVComplianceGuard.sol";
import {BitVRoleConsumer} from "../access/BitVRoleConsumer.sol";
import {BitVPoolManager} from "./BitVPoolManager.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {PercentageMath} from "../libraries/PercentageMath.sol";
import {ProtocolErrors} from "../libraries/ProtocolErrors.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/**
 * @title BitVLendingManager
 * @notice Identity-gated, cross-margin lending core. Owns collateral and
 * debt accounting per user; borrows/repays flow through the registered
 * BitVPoolManager, which owns pool-level liquidity. Not RWA-specific and
 * not yet BitScore-aware — risk parameters come from BitVPoolManager's
 * per-asset config (LTV / liquidation threshold / liquidation bonus),
 * settable by RISK_MANAGER_ROLE, per this milestone's scope.
 *
 * Trust boundary: this contract is the single address BitVPoolManager
 * grants `borrowFromPool`/`repayToPool` access to (see
 * `BitVPoolManager.lendingManager` / `onlyLendingManager`). It is not
 * meant to be one of several callers — a future Factory-mode-style
 * design would need a different trust model.
 */
contract BitVLendingManager is BitVComplianceGuard, BitVRoleConsumer, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Max share of a single position's debt (per asset) a single
    /// liquidation call may repay. 50% is a common, documented industry
    /// default (e.g. Aave v2/v3's close factor) — configurable in case
    /// risk management needs to tune it, not because 50% is derived from
    /// anything BitV-specific.
    uint16 public closeFactorBps = 5_000;

    BitVPoolManager public immutable POOL_MANAGER;
    address public immutable TREASURY;

    mapping(address user => mapping(address asset => uint256)) private _collateralBalance;
    mapping(address user => mapping(address asset => uint256)) private _scaledDebt;
    mapping(address user => EnumerableSet.AddressSet) private _userCollateralAssets;
    mapping(address user => EnumerableSet.AddressSet) private _userDebtAssets;

    event CollateralDeposited(address indexed user, address indexed asset, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed asset, uint256 amount);
    event Borrowed(address indexed user, address indexed asset, uint256 amount);
    event Repaid(address indexed user, address indexed asset, uint256 amount);
    event Liquidated(
        address indexed user,
        address indexed liquidator,
        address debtAsset,
        address collateralAsset,
        uint256 repaidAmount,
        uint256 seizedCollateral
    );
    event CloseFactorUpdated(uint16 closeFactorBps);

    constructor(
        address complianceValidator,
        address owner_,
        address accessManager,
        address poolManager,
        address treasury_
    ) BitVComplianceGuard(complianceValidator, owner_) BitVRoleConsumer(accessManager) {
        if (poolManager == address(0) || treasury_ == address(0)) revert ProtocolErrors.ZeroAddress();
        POOL_MANAGER = BitVPoolManager(poolManager);
        TREASURY = treasury_;
    }

    function setCloseFactor(uint16 bps) external onlyRole(ACCESS_MANAGER.RISK_MANAGER_ROLE()) {
        if (bps == 0 || bps > 10_000) revert ProtocolErrors.InvalidRiskParams();
        closeFactorBps = bps;
        emit CloseFactorUpdated(bps);
    }

    // ── Collateral ───────────────────────────────────────────────────────

    function depositCollateral(address asset, uint256 amount) external nonReentrant {
        _requireCompliance(msg.sender);
        if (amount == 0) revert ProtocolErrors.ZeroAmount();

        DataTypes.Pool memory pool = POOL_MANAGER.getPool(asset);
        if (!pool.isActive) revert ProtocolErrors.PoolNotActive(asset);
        if (!pool.isCollateralEnabled) revert ProtocolErrors.CollateralDisabled(asset);

        _collateralBalance[msg.sender][asset] += amount;
        _userCollateralAssets[msg.sender].add(asset);

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        emit CollateralDeposited(msg.sender, asset, amount);
    }

    function withdrawCollateral(address asset, uint256 amount) external nonReentrant {
        _requireCompliance(msg.sender);
        if (amount == 0) revert ProtocolErrors.ZeroAmount();

        uint256 balance = _collateralBalance[msg.sender][asset];
        if (amount > balance) revert ProtocolErrors.AmountExceedsBalance(amount, balance);

        _accrueAllUserAssets(msg.sender);

        _collateralBalance[msg.sender][asset] = balance - amount;
        if (_collateralBalance[msg.sender][asset] == 0) _userCollateralAssets[msg.sender].remove(asset);

        DataTypes.AccountData memory data = _accountData(msg.sender);
        if (data.totalDebtValue > 0 && data.healthFactorRay < WadRayMath.RAY) {
            revert ProtocolErrors.InsufficientCollateral(data.totalDebtValue, data.totalCollateralValue);
        }

        IERC20(asset).safeTransfer(msg.sender, amount);

        emit CollateralWithdrawn(msg.sender, asset, amount);
    }

    // ── Borrow / Repay ───────────────────────────────────────────────────

    function borrow(address asset, uint256 amount) external nonReentrant {
        _requireCompliance(msg.sender);
        if (amount == 0) revert ProtocolErrors.ZeroAmount();

        DataTypes.Pool memory pool = POOL_MANAGER.getPool(asset);
        if (!pool.isActive) revert ProtocolErrors.PoolNotActive(asset);
        if (!pool.isBorrowingEnabled) revert ProtocolErrors.BorrowingDisabled(asset);
        if (pool.priceOracle == address(0)) revert ProtocolErrors.PriceOracleNotSet(asset);

        _accrueAllUserAssets(msg.sender);
        POOL_MANAGER.accrueInterest(asset);

        DataTypes.AccountData memory data = _accountData(msg.sender);
        uint256 borrowValue = _valueOf(asset, amount, pool.priceOracle);
        if (borrowValue > data.availableBorrowValue) {
            revert ProtocolErrors.InsufficientCollateral(borrowValue, data.availableBorrowValue);
        }

        uint256 scaledAmount = POOL_MANAGER.borrowFromPool(asset, amount, msg.sender);
        _scaledDebt[msg.sender][asset] += scaledAmount;
        _userDebtAssets[msg.sender].add(asset);

        emit Borrowed(msg.sender, asset, amount);
    }

    function repay(address asset, uint256 amount) external nonReentrant returns (uint256 repaid) {
        _requireCompliance(msg.sender);
        if (amount == 0) revert ProtocolErrors.ZeroAmount();

        POOL_MANAGER.accrueInterest(asset);
        uint256 currentDebt = _currentDebt(msg.sender, asset);
        if (currentDebt == 0) revert ProtocolErrors.NoOutstandingDebt(asset);

        repaid = amount > currentDebt ? currentDebt : amount;

        uint256 scaledRepay = repaid.rayDiv(POOL_MANAGER.getBorrowIndex(asset));
        uint256 scaledDebt = _scaledDebt[msg.sender][asset];
        _scaledDebt[msg.sender][asset] = scaledRepay >= scaledDebt ? 0 : scaledDebt - scaledRepay;
        if (_scaledDebt[msg.sender][asset] == 0) _userDebtAssets[msg.sender].remove(asset);

        IERC20(asset).safeTransferFrom(msg.sender, address(POOL_MANAGER), repaid);
        POOL_MANAGER.repayToPool(asset, repaid);

        emit Repaid(msg.sender, asset, repaid);
    }

    // ── Liquidation ──────────────────────────────────────────────────────

    function liquidate(address user, address debtAsset, address collateralAsset, uint256 repayAmount)
        external
        nonReentrant
    {
        _requireCompliance(msg.sender);

        _accrueAllUserAssets(user);

        DataTypes.AccountData memory data = _accountData(user);
        if (data.totalDebtValue == 0) revert ProtocolErrors.NoOutstandingDebt(debtAsset);
        if (data.healthFactorRay >= WadRayMath.RAY) revert ProtocolErrors.PositionIsHealthy(data.healthFactorRay);

        uint256 currentDebt = _currentDebt(user, debtAsset);
        if (currentDebt == 0) revert ProtocolErrors.NoOutstandingDebt(debtAsset);

        uint256 maxRepay = currentDebt.percentMul(closeFactorBps);
        uint256 actualRepay = repayAmount > maxRepay ? maxRepay : repayAmount;
        if (actualRepay > currentDebt) actualRepay = currentDebt;
        if (actualRepay == 0) revert ProtocolErrors.ZeroAmount();

        DataTypes.Pool memory debtPool = POOL_MANAGER.getPool(debtAsset);
        DataTypes.Pool memory collateralPool = POOL_MANAGER.getPool(collateralAsset);
        if (debtPool.priceOracle == address(0)) revert ProtocolErrors.PriceOracleNotSet(debtAsset);
        if (collateralPool.priceOracle == address(0)) revert ProtocolErrors.PriceOracleNotSet(collateralAsset);

        uint256 repayValue = _valueOf(debtAsset, actualRepay, debtPool.priceOracle);
        uint256 seizeValue = repayValue.percentMul(10_000 + collateralPool.liquidationBonusBps);
        uint256 seizeAmount = _amountFromValue(collateralAsset, seizeValue, collateralPool.priceOracle);

        uint256 userCollateral = _collateralBalance[user][collateralAsset];
        if (seizeAmount > userCollateral) {
            // Insolvent position: cap seizure at what's actually there and
            // scale the repay down proportionally, so the liquidator never
            // pays more than the collateral they receive is worth. This
            // can leave residual (unrepaid, uncollateralized) "bad debt"
            // on the position — documented in
            // docs/protocol-architecture.md's security-assumptions
            // section, not silently hidden.
            seizeAmount = userCollateral;
            uint256 cappedSeizeValue = _valueOf(collateralAsset, seizeAmount, collateralPool.priceOracle);
            uint256 cappedRepayValue = cappedSeizeValue.percentDiv(10_000 + collateralPool.liquidationBonusBps);
            actualRepay = _amountFromValue(debtAsset, cappedRepayValue, debtPool.priceOracle);
            if (actualRepay > currentDebt) actualRepay = currentDebt;
        }
        if (actualRepay == 0 || seizeAmount == 0) revert ProtocolErrors.ZeroAmount();

        _collateralBalance[user][collateralAsset] = userCollateral - seizeAmount;
        if (_collateralBalance[user][collateralAsset] == 0) _userCollateralAssets[user].remove(collateralAsset);

        uint256 scaledRepay = actualRepay.rayDiv(POOL_MANAGER.getBorrowIndex(debtAsset));
        uint256 scaledDebt = _scaledDebt[user][debtAsset];
        _scaledDebt[user][debtAsset] = scaledRepay >= scaledDebt ? 0 : scaledDebt - scaledRepay;
        if (_scaledDebt[user][debtAsset] == 0) _userDebtAssets[user].remove(debtAsset);

        IERC20(debtAsset).safeTransferFrom(msg.sender, address(POOL_MANAGER), actualRepay);
        POOL_MANAGER.repayToPool(debtAsset, actualRepay);
        IERC20(collateralAsset).safeTransfer(msg.sender, seizeAmount);

        emit Liquidated(user, msg.sender, debtAsset, collateralAsset, actualRepay, seizeAmount);
    }

    // ── Views ────────────────────────────────────────────────────────────

    function getCollateralBalance(address user, address asset) external view returns (uint256) {
        return _collateralBalance[user][asset];
    }

    function getCurrentDebt(address user, address asset) external view returns (uint256) {
        return _currentDebt(user, asset);
    }

    function getUserAccountData(address user) external view returns (DataTypes.AccountData memory) {
        return _accountData(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _accountData(user).healthFactorRay;
    }

    // ── Internal accounting ──────────────────────────────────────────────

    function _accrueAllUserAssets(address user) internal {
        address[] memory debtAssets = _userDebtAssets[user].values();
        for (uint256 i = 0; i < debtAssets.length; i++) {
            POOL_MANAGER.accrueInterest(debtAssets[i]);
        }
    }

    function _currentDebt(address user, address asset) internal view returns (uint256) {
        uint256 scaled = _scaledDebt[user][asset];
        if (scaled == 0) return 0;
        return scaled.rayMul(POOL_MANAGER.getBorrowIndex(asset));
    }

    /// @dev Aggregates collateral/debt value across every asset the user
    /// has a nonzero position in. Assets whose pool has no configured
    /// price oracle are skipped rather than reverting the whole
    /// calculation — documented limitation: such assets don't count
    /// toward collateral or debt value until a RISK_MANAGER_ROLE holder
    /// configures a price oracle for them.
    function _accountData(address user) internal view returns (DataTypes.AccountData memory data) {
        address[] memory collateralAssets = _userCollateralAssets[user].values();
        uint256 totalCollateralValue;
        uint256 weightedLtvValue;
        uint256 weightedLiqThresholdValue;

        for (uint256 i = 0; i < collateralAssets.length; i++) {
            address asset = collateralAssets[i];
            uint256 balance = _collateralBalance[user][asset];
            if (balance == 0) continue;

            DataTypes.Pool memory pool = POOL_MANAGER.getPool(asset);
            if (pool.priceOracle == address(0)) continue;

            uint256 value = _valueOf(asset, balance, pool.priceOracle);
            totalCollateralValue += value;
            weightedLtvValue += value.percentMul(pool.ltvBps);
            weightedLiqThresholdValue += value.percentMul(pool.liquidationThresholdBps);
        }

        address[] memory debtAssets = _userDebtAssets[user].values();
        uint256 totalDebtValue;

        for (uint256 i = 0; i < debtAssets.length; i++) {
            address asset = debtAssets[i];
            uint256 debt = _currentDebt(user, asset);
            if (debt == 0) continue;

            DataTypes.Pool memory pool = POOL_MANAGER.getPool(asset);
            if (pool.priceOracle == address(0)) continue;

            totalDebtValue += _valueOf(asset, debt, pool.priceOracle);
        }

        data.totalCollateralValue = totalCollateralValue;
        data.totalDebtValue = totalDebtValue;
        data.availableBorrowValue = weightedLtvValue > totalDebtValue ? weightedLtvValue - totalDebtValue : 0;
        data.currentLiquidationThresholdBps =
            totalCollateralValue == 0 ? 0 : (weightedLiqThresholdValue * 10_000) / totalCollateralValue;
        data.healthFactorRay =
            totalDebtValue == 0 ? type(uint256).max : weightedLiqThresholdValue.rayDiv(totalDebtValue);
    }

    /// @dev Normalizes `amount` of `asset` (in the asset's own decimals)
    /// to an 18-decimal "value" unit using `oracle`'s price, so different
    /// assets' values are directly comparable/summable. Requires the
    /// oracle's `decimals` to be <= 18.
    function _valueOf(address asset, uint256 amount, address oracle) internal view returns (uint256) {
        (uint256 price, uint8 priceDecimals) = IPriceOracle(oracle).getPrice(asset);
        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        return (amount * price * (10 ** (18 - priceDecimals))) / (10 ** assetDecimals);
    }

    /// @dev Inverse of `_valueOf`.
    function _amountFromValue(address asset, uint256 valueE18, address oracle) internal view returns (uint256) {
        (uint256 price, uint8 priceDecimals) = IPriceOracle(oracle).getPrice(asset);
        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        return (valueE18 * (10 ** assetDecimals)) / (price * (10 ** (18 - priceDecimals)));
    }
}
