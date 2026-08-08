// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { BaseModule } from "./BaseModule.sol";
import { ILendingManager } from "../interfaces/ILendingManager.sol";
import { IPoolManager } from "../interfaces/IPoolManager.sol";
import { IAccessManager } from "../interfaces/IAccessManager.sol";
import { IIdentityOracle } from "../interfaces/IIdentityOracle.sol";
import { IBitScoreManager } from "../interfaces/IBitScoreManager.sol";
import { IPriceOracle } from "../interfaces/IPriceOracle.sol";
import { DataTypes } from "../libraries/DataTypes.sol";
import { WadRayMath } from "../libraries/WadRayMath.sol";
import { PercentageMath } from "../libraries/PercentageMath.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title LendingManager
/// @notice Debt side of BitV's lending markets: collateral, borrowing
///         (collateralized AND identity-based under-collateralized credit),
///         repayment, health factor, and liquidation.
///
/// @dev RISK MODEL — read before treating `healthFactor` as a standard
///      over-collateralized money-market health factor, because it is not:
///
///          healthFactor = (collateralValueAtLiquidationThreshold + creditLimitUsd)
///                         * 1e18 / totalDebtUsd
///
///      The numerator includes `creditLimitUsd` — the BitScore-derived
///      UNSECURED credit ceiling — alongside actual posted collateral. This
///      is intentional and is the entire point of the product (identity
///      substitutes for a slice of collateral), but it means a liquidation
///      can only ever recover value from what's ACTUALLY posted as
///      collateral: the unsecured portion of a defaulted position has
///      nothing to seize. `liquidate` therefore caps seizure at the
///      borrower's real collateral balance and can leave residual bad debt
///      for the unsecured slice — accepted, not hidden, as the risk premium
///      of under-collateralized lending, and why every liquidation reports a
///      severe BitScore penalty (`IBitScoreManager.ScoreEvent.Liquidated`)
///      rather than treating it as routine. See
///      `docs/contracts-architecture.md` §Risk model for the full treatment,
///      including the bad-debt backstop this repo leaves as a documented v2
///      (Treasury-funded insurance fund).
///
/// @dev DEBT INDEX OWNERSHIP — this contract does NOT maintain its own
///      borrow index or `totalScaledDebt`. Both live on `PoolManager`'s
///      `Pool` struct and are the single source of truth for a market's debt
///      value — see the NatSpec on `DataTypes.Pool` for why an earlier design
///      that split the index across both contracts caused a real,
///      usage-scaling solvency drift (documented and fixed; see
///      `docs/contracts-architecture.md` §Known issues, now resolved). This
///      contract owns exactly two things per account: `collateral` and
///      `DebtPosition.scaledDebt` (a SHARE of PoolManager's total, scaled at
///      PoolManager's index) — every read of "how much debt" calls into
///      PoolManager for the current index rather than compounding one
///      locally.
/// @custom:storage-location erc7201:bitv.storage.LendingManager
contract LendingManager is BaseModule, ILendingManager {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    struct LendingManagerStorage {
        mapping(address asset => DataTypes.BorrowConfig) borrowConfigs;
        mapping(address account => mapping(address asset => uint256 amount)) collateral;
        mapping(address account => mapping(address asset => DataTypes.DebtPosition)) debtPositions;
        address[] listedAssets;
    }

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("bitv.storage.LendingManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0xfeedbc54d95979bad6910b37fc6c3a5b418a8732688a6e5725de6b3f0a32ae00;

    function _s() private pure returns (LendingManagerStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address registry_, address admin) external initializer {
        __BaseModule_init(registry_, admin);
    }

    // ── Configuration ────────────────────────────────────────────────────

    function setBorrowConfig(address asset, DataTypes.BorrowConfig calldata config)
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        if (config.collateralFactorBps > config.liquidationThresholdBps) {
            // LTV above liquidation threshold would mean a position is
            // opened already eligible for liquidation — a parameter error,
            // not a valid risk configuration, so this must fail closed.
            revert Errors.InvalidRateModelParams();
        }
        if (
            config.collateralFactorBps > PercentageMath.BPS_DENOMINATOR
                || config.liquidationThresholdBps > PercentageMath.BPS_DENOMINATOR
                || config.liquidationBonusBps > PercentageMath.BPS_DENOMINATOR
                || config.closeFactorBps > PercentageMath.BPS_DENOMINATOR
        ) {
            revert Errors.InvalidBps(PercentageMath.BPS_DENOMINATOR);
        }

        DataTypes.BorrowConfig storage existing = _s().borrowConfigs[asset];
        if (!existing.isListed) {
            _s().listedAssets.push(asset);
        }

        existing.isListed = true;
        existing.borrowCap = config.borrowCap;
        existing.collateralFactorBps = config.collateralFactorBps;
        existing.liquidationThresholdBps = config.liquidationThresholdBps;
        existing.liquidationBonusBps = config.liquidationBonusBps;
        existing.closeFactorBps = config.closeFactorBps;
        existing.isCollateralEligible = config.isCollateralEligible;

        emit BorrowConfigUpdated(asset, existing);
        if (config.isCollateralEligible) {
            emit AssetListedAsCollateral(asset, config.collateralFactorBps, config.liquidationThresholdBps);
        }
    }

    // ── Collateral ───────────────────────────────────────────────────────

    function depositCollateral(address asset, uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert Errors.ZeroAmount();
        if (!_s().borrowConfigs[asset].isCollateralEligible) revert Errors.AssetNotSupported(asset);

        _s().collateral[msg.sender][asset] += amount;
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        emit CollateralDeposited(msg.sender, asset, amount);
    }

    function withdrawCollateral(address asset, uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert Errors.ZeroAmount();

        uint256 balance = _s().collateral[msg.sender][asset];
        if (amount > balance) revert Errors.AmountExceedsBalance(amount, balance);

        _s().collateral[msg.sender][asset] = balance - amount;

        // Health factor is re-checked AFTER the tentative withdrawal using
        // the same aggregation the getter uses — a withdrawal that would
        // leave the account liquidatable is rejected outright rather than
        // allowed and immediately flagged, since permitting it would let a
        // borrower race a liquidator to strip collateral out of an already-
        // risky position.
        if (_hasDebt(msg.sender)) {
            uint256 hf = healthFactor(msg.sender);
            if (hf < WadRayMath.WAD) {
                _s().collateral[msg.sender][asset] = balance; // revert state
                revert Errors.HealthFactorTooLow(hf);
            }
        }

        IERC20(asset).safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, asset, amount);
    }

    // ── Borrow / repay ───────────────────────────────────────────────────

    function borrow(address asset, uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert Errors.ZeroAmount();

        DataTypes.BorrowConfig storage config = _s().borrowConfigs[asset];
        if (!config.isListed) revert Errors.AssetNotSupported(asset);

        IAccessManager(registry().requireAddress(registry().ACCESS_MANAGER())).requireCapability(
            IAccessManager.Capability.AccessBorrowing, msg.sender
        );

        address poolManager = registry().requireAddress(registry().POOL_MANAGER());
        // Accrue BEFORE reading any debt or borrow-cap figures below, so the
        // eligibility check and `borrowFromPool`'s own internal accrual (a
        // cheap no-op re-entry, since it runs in the same transaction at the
        // same `block.timestamp`) use the identical, up-to-date index.
        IPoolManager(poolManager).accrueInterest(asset);

        IPriceOracle oracle = IPriceOracle(registry().requireAddress(registry().PRICE_ORACLE()));
        uint256 amountUsd = _toWad(asset, amount).wadMul(oracle.getPriceUsd(asset));

        uint256 debtBeforeUsd = _totalDebtUsd(msg.sender, oracle);
        uint256 power = borrowingPowerUsd(msg.sender);
        if (debtBeforeUsd + amountUsd > power) {
            revert Errors.CreditLineExceeded(msg.sender, debtBeforeUsd + amountUsd, power);
        }

        if (config.borrowCap != 0) {
            uint256 newTotalBorrowed = IPoolManager(poolManager).totalBorrowed(asset) + amount;
            if (newTotalBorrowed > config.borrowCap) {
                revert Errors.BorrowCapExceeded(_marketId(asset), newTotalBorrowed, config.borrowCap);
            }
        }

        bool underCollateralized = debtBeforeUsd + amountUsd > _collateralValueUsd(msg.sender, oracle, false);

        // `borrowFromPool` accrues (no-op here, already fresh), moves the
        // underlying, and returns the scaled amount AT THE INDEX IT USED —
        // applying that exact value here is what keeps
        // `sum(position.scaledDebt) == pool.totalScaledDebt` exact, see
        // `IPoolManager.borrowFromPool`.
        uint256 scaledIncrease = IPoolManager(poolManager).borrowFromPool(asset, amount, msg.sender);

        DataTypes.DebtPosition storage position = _s().debtPositions[msg.sender][asset];
        position.scaledDebt += uint128(scaledIncrease);
        position.lastBorrowTimestamp = uint40(block.timestamp);

        emit Borrowed(msg.sender, asset, amount, underCollateralized);
    }

    function repay(address asset, uint256 amount, address onBehalfOf)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 repaid)
    {
        if (amount == 0) revert Errors.ZeroAmount();

        DataTypes.BorrowConfig storage config = _s().borrowConfigs[asset];
        if (!config.isListed) revert Errors.AssetNotSupported(asset);

        address poolManager = registry().requireAddress(registry().POOL_MANAGER());
        IPoolManager(poolManager).accrueInterest(asset);
        (, uint256 borrowIndexRay) = IPoolManager(poolManager).previewAccruedIndices(asset);

        DataTypes.DebtPosition storage position = _s().debtPositions[onBehalfOf][asset];
        uint256 currentDebt = uint256(position.scaledDebt).rayMul(borrowIndexRay);
        if (currentDebt == 0) revert Errors.NoOutstandingDebt(onBehalfOf, _marketId(asset));

        repaid = amount > currentDebt ? currentDebt : amount;

        IERC20(asset).safeTransferFrom(msg.sender, address(this), repaid);
        IERC20(asset).forceApprove(poolManager, repaid);

        // Same pattern as `borrow`: PoolManager computes the scaled decrease
        // at the index it actually used and returns it, rather than this
        // contract re-deriving it from a value it read a moment earlier.
        uint256 scaledDecrease = IPoolManager(poolManager).notifyRepay(asset, repaid);
        position.scaledDebt -= uint128(scaledDecrease);

        _reportBitScoreIfAuthorized(
            onBehalfOf, IBitScoreManager.ScoreEvent.OnTimeRepayment, repaid
        );

        emit Repaid(onBehalfOf, asset, repaid, msg.sender);
    }

    // ── Liquidation ──────────────────────────────────────────────────────

    function liquidate(
        address borrower,
        address debtAsset,
        address collateralAsset,
        uint256 debtToCover
    ) external whenNotPaused nonReentrant returns (uint256 collateralSeized) {
        uint256 hf = healthFactor(borrower);
        if (hf >= WadRayMath.WAD) revert Errors.HealthFactorAboveLiquidationThreshold(hf);

        DataTypes.BorrowConfig storage debtConfig = _s().borrowConfigs[debtAsset];
        DataTypes.BorrowConfig storage collateralConfig = _s().borrowConfigs[collateralAsset];
        if (!debtConfig.isListed) revert Errors.AssetNotSupported(debtAsset);
        if (!collateralConfig.isCollateralEligible) revert Errors.AssetNotSupported(collateralAsset);

        address poolManager = registry().requireAddress(registry().POOL_MANAGER());
        IPoolManager(poolManager).accrueInterest(debtAsset);
        (, uint256 borrowIndexRay) = IPoolManager(poolManager).previewAccruedIndices(debtAsset);

        DataTypes.DebtPosition storage position = _s().debtPositions[borrower][debtAsset];
        uint256 currentDebt = uint256(position.scaledDebt).rayMul(borrowIndexRay);
        if (currentDebt == 0) revert Errors.NoOutstandingDebt(borrower, _marketId(debtAsset));

        uint256 maxRepayable = currentDebt.percentMul(debtConfig.closeFactorBps);
        if (debtToCover > maxRepayable) revert Errors.CloseFactorExceeded(debtToCover, maxRepayable);

        IPriceOracle oracle = IPriceOracle(registry().requireAddress(registry().PRICE_ORACLE()));
        uint256 debtToCoverUsd = _toWad(debtAsset, debtToCover).wadMul(oracle.getPriceUsd(debtAsset));
        uint256 seizeUsd = debtToCoverUsd.percentMul(
            PercentageMath.BPS_DENOMINATOR + collateralConfig.liquidationBonusBps
        );
        // `seizeUsd.wadDiv(price)` yields a WAD (18-decimal) quantity of
        // collateral; `_fromWad` converts it to the collateral asset's own
        // native decimals before it is compared against or subtracted from
        // `_s().collateral`, which is stored in native units.
        collateralSeized = _fromWad(collateralAsset, seizeUsd.wadDiv(oracle.getPriceUsd(collateralAsset)));

        uint256 available = _s().collateral[borrower][collateralAsset];
        if (collateralSeized > available) {
            // See the contract-level risk-model note: this is the "not
            // enough posted collateral to cover an under-collateralized
            // shortfall" case. Reverting here rather than partially seizing
            // keeps this function's accounting exact; a liquidator hitting
            // this should reduce `debtToCover`, and the residual bad debt is
            // handled by the (documented, v2) treasury backstop rather than
            // by this call silently doing a different trade than requested.
            revert Errors.AmountExceedsBalance(collateralSeized, available);
        }

        _s().collateral[borrower][collateralAsset] = available - collateralSeized;

        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), debtToCover);
        IERC20(debtAsset).forceApprove(poolManager, debtToCover);
        uint256 scaledDecrease = IPoolManager(poolManager).notifyRepay(debtAsset, debtToCover);
        position.scaledDebt -= uint128(scaledDecrease);

        IERC20(collateralAsset).safeTransfer(msg.sender, collateralSeized);

        _reportBitScoreIfAuthorized(borrower, IBitScoreManager.ScoreEvent.Liquidated, debtToCoverUsd);

        emit Liquidated(borrower, msg.sender, debtAsset, collateralAsset, debtToCover, collateralSeized);
    }

    // ── Views ────────────────────────────────────────────────────────────

    function healthFactor(address account) public view returns (uint256) {
        IPriceOracle oracle = IPriceOracle(registry().requireAddress(registry().PRICE_ORACLE()));
        uint256 debtUsd = _totalDebtUsd(account, oracle);
        if (debtUsd == 0) return type(uint256).max;

        uint256 coverageUsd = _collateralValueUsd(account, oracle, true) + _creditLimitUsd(account);
        return coverageUsd.wadDiv(debtUsd);
    }

    function debtOf(address account, address asset) external view returns (uint256) {
        uint256 borrowIndexRay = _previewBorrowIndex(asset);
        return uint256(_s().debtPositions[account][asset].scaledDebt).rayMul(borrowIndexRay);
    }

    function collateralOf(address account, address asset) external view returns (uint256) {
        return _s().collateral[account][asset];
    }

    function getBorrowConfig(address asset) external view returns (DataTypes.BorrowConfig memory) {
        return _s().borrowConfigs[asset];
    }

    function borrowingPowerUsd(address account) public view returns (uint256) {
        IPriceOracle oracle = IPriceOracle(registry().requireAddress(registry().PRICE_ORACLE()));
        return _collateralValueUsd(account, oracle, false) + _creditLimitUsd(account);
    }

    // ── Internal aggregation ─────────────────────────────────────────────

    /// @param useThreshold true = liquidation-threshold weighting (health
    ///        factor), false = collateral-factor / LTV weighting (borrow
    ///        eligibility). The two use different bps per asset by design —
    ///        see the contract-level risk-model note.
    function _collateralValueUsd(address account, IPriceOracle oracle, bool useThreshold)
        internal
        view
        returns (uint256 totalUsd)
    {
        address[] storage assets = _s().listedAssets;
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 amount = _s().collateral[account][asset];
            if (amount == 0) continue;

            DataTypes.BorrowConfig storage config = _s().borrowConfigs[asset];
            if (!config.isCollateralEligible) continue;
            if (!oracle.isPriceAvailable(asset)) continue;

            uint256 valueUsd = _toWad(asset, amount).wadMul(oracle.getPriceUsd(asset));
            uint16 weightBps = useThreshold ? config.liquidationThresholdBps : config.collateralFactorBps;
            totalUsd += valueUsd.percentMul(weightBps);
        }
    }

    function _totalDebtUsd(address account, IPriceOracle oracle) internal view returns (uint256 totalUsd) {
        address[] storage assets = _s().listedAssets;
        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 scaledDebt = _s().debtPositions[account][asset].scaledDebt;
            if (scaledDebt == 0) continue;
            if (!oracle.isPriceAvailable(asset)) continue;

            uint256 borrowIndexRay = _previewBorrowIndex(asset);
            uint256 debt = scaledDebt.rayMul(borrowIndexRay);
            totalUsd += _toWad(asset, debt).wadMul(oracle.getPriceUsd(asset));
        }
    }

    function _hasDebt(address account) internal view returns (bool) {
        address[] storage assets = _s().listedAssets;
        for (uint256 i = 0; i < assets.length; i++) {
            if (_s().debtPositions[account][assets[i]].scaledDebt > 0) return true;
        }
        return false;
    }

    function _creditLimitUsd(address account) internal view returns (uint256) {
        address bitScoreManagerAddr = registry().getAddress(registry().BITSCORE_MANAGER());
        address identityOracleAddr = registry().getAddress(registry().IDENTITY_ORACLE());
        if (bitScoreManagerAddr == address(0) || identityOracleAddr == address(0)) return 0;

        uint16 tier = IIdentityOracle(identityOracleAddr).tierOf(account);
        return IBitScoreManager(bitScoreManagerAddr).creditLimitUsd(account, tier);
    }

    function _reportBitScoreIfAuthorized(address account, IBitScoreManager.ScoreEvent evt, uint256 magnitudeWad)
        internal
    {
        address bitScoreManagerAddr = registry().getAddress(registry().BITSCORE_MANAGER());
        if (bitScoreManagerAddr == address(0)) return;
        // Deliberately not `try/catch`-wrapped: BitScoreManager explicitly
        // authorizing this contract as a reporter (`setReporterAuthorized`)
        // is part of the deployment wiring, so a revert here means wiring is
        // broken and SHOULD surface loudly rather than silently skip a
        // reputation update.
        IBitScoreManager(bitScoreManagerAddr).reportEvent(account, evt, magnitudeWad);
    }

    /// @dev `view`-safe current borrow index for `asset`, read from
    ///      PoolManager (the sole owner of it) rather than any local state —
    ///      see the contract-level NatSpec on debt index ownership.
    function _previewBorrowIndex(address asset) internal view returns (uint256) {
        address poolManager = registry().requireAddress(registry().POOL_MANAGER());
        (, uint256 borrowIndexRay) = IPoolManager(poolManager).previewAccruedIndices(asset);
        return borrowIndexRay;
    }

    function _marketId(address asset) internal pure returns (bytes32) {
        return keccak256(abi.encode(asset));
    }

    /// @dev Converts a raw token amount (in `asset`'s own decimals — 6 for
    ///      USDC, 18 for WETH, etc.) to an 18-decimal (WAD) equivalent, which
    ///      is the scale every USD price from `IPriceOracle` and every
    ///      `WadRayMath` operation in this contract assumes. This is NOT
    ///      optional bookkeeping: multiplying a raw 6-decimal USDC amount
    ///      directly by a WAD price under-values it by exactly 10^12,
    ///      silently — every USD aggregation in this contract
    ///      (`_collateralValueUsd`, `_totalDebtUsd`, `borrow`'s eligibility
    ///      check, `liquidate`'s seizure math) routes through this so that
    ///      bug class cannot recur asset-by-asset.
    function _toWad(address asset, uint256 amount) internal view returns (uint256) {
        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        if (assetDecimals == 18) return amount;
        if (assetDecimals < 18) return amount * (10 ** (18 - assetDecimals));
        return amount / (10 ** (assetDecimals - 18));
    }

    /// @dev Inverse of `_toWad` — converts a WAD (18-decimal) quantity back
    ///      to `asset`'s native decimals. Used in `liquidate` to convert the
    ///      USD-derived seizure amount into the actual token units the
    ///      collateral ledger (`_s().collateral`, stored in native decimals)
    ///      is denominated in.
    function _fromWad(address asset, uint256 wadAmount) internal view returns (uint256) {
        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        if (assetDecimals == 18) return wadAmount;
        if (assetDecimals < 18) return wadAmount / (10 ** (18 - assetDecimals));
        return wadAmount * (10 ** (assetDecimals - 18));
    }
}
