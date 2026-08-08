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
import {IBitScoreManager} from "../interfaces/IBitScoreManager.sol";

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

    /// @notice Optional (Build 04). address(0) = BitScore disabled —
    /// every lending action falls back to base, score-independent
    /// parameters, per docs/bitscore-specification.md §12's fail-safe
    /// requirement. Never required for CVI compliance, which remains
    /// mandatory and unaffected regardless of this being set.
    IBitScoreManager public bitScoreManager;

    mapping(address user => mapping(address asset => uint256)) private _collateralBalance;
    mapping(address user => mapping(address asset => uint256)) private _scaledDebt;
    mapping(address user => mapping(address asset => uint40)) private _debtOpenedTimestamp;
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
    event BitScoreManagerSet(address indexed bitScoreManager);
    event BitScoreUpdateFailed(address indexed user, bytes32 indexed action);

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

    /// @notice Wires BitScore into lending. Pass address(0) to disable
    /// (fall back to base parameters for everyone) — never required for
    /// the protocol to function, since CVI compliance is the only hard
    /// eligibility gate.
    function setBitScoreManager(address bitScoreManager_) external onlyRole(ACCESS_MANAGER.PROTOCOL_ADMIN_ROLE()) {
        bitScoreManager = IBitScoreManager(bitScoreManager_);
        emit BitScoreManagerSet(bitScoreManager_);
    }

    // ── Collateral ───────────────────────────────────────────────────────

    function depositCollateral(address asset, uint256 amount) external nonReentrant {
        _requireCompliance(msg.sender);
        if (amount == 0) revert ProtocolErrors.ZeroAmount();

        DataTypes.Pool memory pool = POOL_MANAGER.getPool(asset);
        if (!pool.isActive) revert ProtocolErrors.PoolNotActive(asset);
        if (pool.isPaused) revert ProtocolErrors.PoolIsPaused(asset);
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
        _recordUtilizationSnapshot(msg.sender, data);

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
        uint256 effectiveAvailable = _effectiveAvailableBorrowValue(msg.sender, data);
        if (borrowValue > effectiveAvailable) {
            revert ProtocolErrors.InsufficientCollateral(borrowValue, effectiveAvailable);
        }

        if (_scaledDebt[msg.sender][asset] == 0) {
            _debtOpenedTimestamp[msg.sender][asset] = uint40(block.timestamp);
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

        // Build 04: support `amount == type(uint256).max` as "repay my
        // exact current debt," mirroring the existing pattern in
        // BitVPoolManager.withdraw(). Interest accrues between a caller
        // reading `getCurrentDebt()` off-chain and their `repay()`
        // transaction landing, so a pre-computed "repay everything"
        // amount is routinely a few wei short of the real current debt
        // by the time this executes — without this sentinel, an
        // intended full close almost never lands as an *exact* full
        // close, which matters here because BitScore's repayment
        // scoring depends on detecting a true full close (see
        // `wasFullClose` below).
        repaid = amount == type(uint256).max ? currentDebt : (amount > currentDebt ? currentDebt : amount);

        // `repaid == currentDebt` is the exact signal for a
        // full close. Deriving it instead from
        // `rayDiv(repaid, index) >= scaledDebt` is unreliable —
        // rayMul/rayDiv both round to nearest independently, so
        // rayDiv(rayMul(scaledDebt, index), index) is not guaranteed to
        // land back at exactly `scaledDebt`; it can come out 1 wei low,
        // which silently left 1 wei of scaled debt behind on every
        // "full" repayment (position never actually reached zero debt,
        // `_userDebtAssets` was never cleared, and BitScore's
        // `wasFullClose` — which depends on this — was never true).
        // Forcing the scaled balance to exactly zero on an exact-amount
        // full close removes the dust instead of leaving it to compound
        // as a latent accounting error.
        bool wasFullClose = repaid == currentDebt;
        uint256 scaledDebt = _scaledDebt[msg.sender][asset];
        if (wasFullClose) {
            _scaledDebt[msg.sender][asset] = 0;
            _userDebtAssets[msg.sender].remove(asset);
        } else {
            uint256 scaledRepay = repaid.rayDiv(POOL_MANAGER.getBorrowIndex(asset));
            _scaledDebt[msg.sender][asset] = scaledRepay >= scaledDebt ? 0 : scaledDebt - scaledRepay;
        }

        uint256 positionDuration = block.timestamp - uint256(_debtOpenedTimestamp[msg.sender][asset]);
        if (wasFullClose) _debtOpenedTimestamp[msg.sender][asset] = 0;

        IERC20(asset).safeTransferFrom(msg.sender, address(POOL_MANAGER), repaid);
        POOL_MANAGER.repayToPool(asset, repaid);
        _recordRepayment(msg.sender, wasFullClose, positionDuration);

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

        uint256 originalDebt = currentDebt;
        bool wasBadDebt = false;

        uint256 userCollateral = _collateralBalance[user][collateralAsset];
        if (seizeAmount > userCollateral) {
            wasBadDebt = true;
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

        bool wasPartial = actualRepay < originalDebt;
        _recordLiquidation(user, wasBadDebt, wasPartial);

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

    /// @notice Base-vs-BitScore-adjusted available borrow value, exposed
    /// for tests/UI without needing to call `borrow`. Same fail-safe
    /// fallback logic as `borrow` itself.
    function getEffectiveAvailableBorrowValue(address user) external view returns (uint256) {
        return _effectiveAvailableBorrowValue(user, _accountData(user));
    }

    /// @notice Quoted (not applied) interest discount for `user`'s
    /// current tier — see IBitScoreManager.getBaseRateDiscountRay's
    /// NatSpec for why this is informational only.
    function getQuotedBaseRateDiscountRay(address user) external view returns (uint256) {
        if (address(bitScoreManager) == address(0)) return 0;
        try bitScoreManager.getBaseRateDiscountRay(user) returns (uint256 discount) {
            return discount;
        } catch {
            return 0;
        }
    }

    // ── Internal accounting ──────────────────────────────────────────────

    /// @dev Build 04 integration point. Falls back to `data.availableBorrowValue`
    /// (the base, score-independent, ltvBps-weighted hard limit) whenever
    /// BitScore is disabled or its call fails for any reason — per
    /// docs/bitscore-specification.md §12, never toward a more favorable
    /// result than what a failure-free base calculation would give.
    function _effectiveAvailableBorrowValue(address user, DataTypes.AccountData memory data)
        internal
        view
        returns (uint256)
    {
        if (address(bitScoreManager) == address(0)) return data.availableBorrowValue;

        uint256 maxAvailable =
            data.weightedMaxLtvValue > data.totalDebtValue ? data.weightedMaxLtvValue - data.totalDebtValue : 0;

        try bitScoreManager.getAdjustedAvailableBorrowValue(
            user, data.availableBorrowValue, maxAvailable, data.totalDebtValue, data.totalCollateralValue
        ) returns (uint256 adjusted) {
            // Defense in depth: even a correctly-implemented BitScoreManager
            // is never trusted to exceed the caller-computed ceiling —
            // this is the "score cannot bypass hard protocol limits"
            // guarantee enforced at the call site, not just by convention.
            return adjusted > maxAvailable ? maxAvailable : adjusted;
        } catch {
            return data.availableBorrowValue;
        }
    }

    function _recordRepayment(address user, bool wasFullClose, uint256 positionDuration) internal {
        if (address(bitScoreManager) == address(0)) return;
        try bitScoreManager.recordRepayment(user, wasFullClose, positionDuration) {}
        catch {
            emit BitScoreUpdateFailed(user, "repayment");
        }
    }

    function _recordLiquidation(address user, bool wasBadDebt, bool wasPartial) internal {
        if (address(bitScoreManager) == address(0)) return;
        try bitScoreManager.recordLiquidation(user, wasBadDebt, wasPartial) {}
        catch {
            emit BitScoreUpdateFailed(user, "liquidation");
        }
    }

    function _recordUtilizationSnapshot(address user, DataTypes.AccountData memory data) internal {
        if (address(bitScoreManager) == address(0)) return;
        uint16 utilizationBps = data.totalCollateralValue == 0
            ? 0
            : uint16(_min(data.totalDebtValue * 10_000 / data.totalCollateralValue, 10_000));
        uint16 healthFactorBps = data.healthFactorRay == type(uint256).max
            ? type(uint16).max
            : uint16(_min(data.healthFactorRay / 1e23, type(uint16).max)); // ray (1e27) -> bps-of-1x (1e4) scale
        try bitScoreManager.recordUtilizationSnapshot(user, utilizationBps, healthFactorBps) {}
        catch {
            emit BitScoreUpdateFailed(user, "utilization_snapshot");
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

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
        uint256 weightedMaxLtvValue;
        uint256 weightedLiqThresholdValue;

        for (uint256 i = 0; i < collateralAssets.length; i++) {
            address asset = collateralAssets[i];
            uint256 balance = _collateralBalance[user][asset];
            if (balance == 0) continue;

            DataTypes.Pool memory pool = POOL_MANAGER.getPool(asset);
            if (pool.priceOracle == address(0)) continue;

            (uint256 value, bool ok) = _tryValueOf(asset, balance, pool.priceOracle);
            if (!ok) continue; // zero-priced (misconfigured) asset — treated like "no oracle", not a DoS

            totalCollateralValue += value;
            weightedLtvValue += value.percentMul(pool.ltvBps);
            weightedMaxLtvValue += value.percentMul(pool.maxLtvWithScoreBps);
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

            (uint256 value, bool ok) = _tryValueOf(asset, debt, pool.priceOracle);
            if (!ok) continue;

            totalDebtValue += value;
        }

        data.totalCollateralValue = totalCollateralValue;
        data.totalDebtValue = totalDebtValue;
        data.availableBorrowValue = weightedLtvValue > totalDebtValue ? weightedLtvValue - totalDebtValue : 0;
        data.weightedMaxLtvValue = weightedMaxLtvValue;
        data.currentLiquidationThresholdBps =
            totalCollateralValue == 0 ? 0 : (weightedLiqThresholdValue * 10_000) / totalCollateralValue;
        data.healthFactorRay =
            totalDebtValue == 0 ? type(uint256).max : weightedLiqThresholdValue.rayDiv(totalDebtValue);
    }

    /// @dev Normalizes `amount` of `asset` (in the asset's own decimals)
    /// to an 18-decimal "value" unit using `oracle`'s price, so different
    /// assets' values are directly comparable/summable. Requires the
    /// oracle's `decimals` to be <= 18. Used by action-specific paths
    /// (borrow's requested-amount check, liquidation's repay/seize
    /// conversions) where the asset in question is the one the caller is
    /// directly acting on right now, so failing loudly on a zero price is
    /// correct — see `_tryValueOf` for the non-reverting variant used
    /// while aggregating a user's whole position.
    function _valueOf(address asset, uint256 amount, address oracle) internal view returns (uint256) {
        (uint256 value, bool ok) = _tryValueOf(asset, amount, oracle);
        if (!ok) revert ProtocolErrors.ZeroPrice(asset);
        return value;
    }

    /// @dev Non-reverting version of `_valueOf`, for `_accountData`'s
    /// aggregation loops. A zero price (oracle misconfigured, distinct
    /// from no oracle being set at all) is treated the same as "no
    /// oracle configured" — skipped rather than reverting — so one
    /// mispriced asset can't deny-of-service every action for every user
    /// who happens to hold it. This is a real, documented risk in the
    /// debt-asset case specifically (a zero-priced debt asset drops out
    /// of `totalDebtValue`, understating risk) — see
    /// docs/economic-engine-review.md.
    function _tryValueOf(address asset, uint256 amount, address oracle) internal view returns (uint256 value, bool ok) {
        (uint256 price, uint8 priceDecimals) = IPriceOracle(oracle).getPrice(asset);
        if (price == 0) return (0, false);
        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        value = (amount * price * (10 ** (18 - priceDecimals))) / (10 ** assetDecimals);
        ok = true;
    }

    /// @dev Inverse of `_valueOf`.
    function _amountFromValue(address asset, uint256 valueE18, address oracle) internal view returns (uint256) {
        (uint256 price, uint8 priceDecimals) = IPriceOracle(oracle).getPrice(asset);
        if (price == 0) revert ProtocolErrors.ZeroPrice(asset);
        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        return (valueE18 * (10 ** assetDecimals)) / (price * (10 ** (18 - priceDecimals)));
    }
}
