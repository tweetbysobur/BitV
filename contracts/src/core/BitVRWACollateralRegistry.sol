// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {BitVRoleConsumer} from "../access/BitVRoleConsumer.sol";
import {BitVPoolManager} from "./BitVPoolManager.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IRWACollateralRegistry} from "../interfaces/IRWACollateralRegistry.sol";
import {RWAErrors} from "../libraries/RWAErrors.sol";

/**
 * @title BitVRWACollateralRegistry
 * @notice Implements docs/rwa-market-specification.md's architecture
 * decision (B): a dedicated registry connected to BitVLendingManager
 * via the narrow IRWACollateralRegistry interface, mirroring
 * BitScoreManager's optional/fail-safe integration pattern (Build 04).
 *
 * This contract owns exactly one responsibility: deciding whether a
 * registered RWA asset's collateral currently counts toward NEW
 * borrowing capacity. It does **not** own collateral accounting, debt
 * accounting, LTV weighting, health-factor computation, borrowing,
 * repayment, or liquidation — those remain entirely
 * BitVLendingManager's, reused unmodified. An RWA asset is still just a
 * BitVPoolManager pool with `isCollateralEnabled = true`; this registry
 * only gates whether that pool's collateral value is eligible for new
 * activity right now.
 *
 * Cleanverse discipline (per docs/rwa-market-specification.md §3/§5/§7):
 * no CVA contract address, API, or verification field is invented here.
 * `AssetConfig.isCVA` is purely admin-attested metadata — Cleanverse
 * exposes no on-chain "is this token a currently-valid CVA" query this
 * contract could call instead, so this is the controlled registry
 * boundary the specification calls for rather than a fabrication.
 */
contract BitVRWACollateralRegistry is BitVRoleConsumer, IRWACollateralRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Per docs/rwa-market-specification.md §12: the
    /// specification's full model has five states (Unregistered,
    /// Verified, Suspended, Frozen, Delisted); this implementation
    /// narrows to the four the task's approved scope justifies —
    /// Unregistered (never registered), Active (the specification's
    /// "Verified"), Frozen, and Delisted. "Suspended" is not
    /// implemented as a separate status: its practical effect
    /// (temporary block on new deposits/borrowing, everything else
    /// continues) is already covered by Frozen, and its
    /// oracle-specific trigger is already covered by the independent
    /// price-staleness check (see `isEligibleForNewActivity`) rather
    /// than needing its own status value.
    enum AssetStatus {
        Unregistered,
        Active,
        Frozen,
        Delisted
    }

    struct AssetConfig {
        AssetStatus status;
        address underlyingPool; // the asset itself — BitVPoolManager keys pools by asset address
        uint16 ltvBps;
        uint16 maxLtvWithScoreBps;
        uint16 liquidationThresholdBps;
        uint16 liquidationBonusBps;
        uint256 collateralCap; // 0 = uncapped
        address oracle; // IPriceOracle — may differ from the pool's own configured oracle
        uint32 maxOracleStalenessSeconds;
        uint40 lastPriceVerifiedTimestamp;
        bool isCVA; // admin-attested metadata only, see contract NatSpec and spec §5/§7
    }

    struct AssetConfigParams {
        uint16 ltvBps;
        uint16 maxLtvWithScoreBps;
        uint16 liquidationThresholdBps;
        uint16 liquidationBonusBps;
        uint256 collateralCap;
        address oracle;
        uint32 maxOracleStalenessSeconds;
        bool isCVA;
    }

    BitVPoolManager public immutable POOL_MANAGER;

    mapping(address asset => AssetConfig) private _assets;
    mapping(address asset => EnumerableSet.AddressSet) private _allowedDebtAssets;

    event AssetRegistered(address indexed asset, address indexed oracle, uint16 ltvBps);
    event AssetConfigUpdated(address indexed asset);
    event AssetStatusChanged(address indexed asset, AssetStatus oldStatus, AssetStatus newStatus);
    event CollateralCapSet(address indexed asset, uint256 cap);
    event OracleConfigSet(address indexed asset, address indexed oracle, uint32 maxStalenessSeconds);
    event PriceMarkedFresh(address indexed asset, uint256 price, uint8 priceDecimals);
    event AllowedDebtAssetSet(address indexed asset, address indexed debtAsset, bool allowed);

    constructor(address accessManager, address poolManager) BitVRoleConsumer(accessManager) {
        if (poolManager == address(0)) revert RWAErrors.ZeroAddress();
        POOL_MANAGER = BitVPoolManager(poolManager);
    }

    // ── Registration & configuration (RWA_ADMIN_ROLE) ──────────────────

    /// @notice Registers `asset` as RWA collateral. Rejects duplicate
    /// registration outright — an asset once registered (at any status,
    /// including Delisted) can never be re-registered under the same
    /// address; see `setAssetStatus`'s NatSpec for why Delisted is
    /// permanent by design.
    function registerAsset(address asset, AssetConfigParams calldata params)
        external
        onlyRole(ACCESS_MANAGER.RWA_ADMIN_ROLE())
    {
        if (asset == address(0) || params.oracle == address(0)) revert RWAErrors.ZeroAddress();
        if (_assets[asset].status != AssetStatus.Unregistered) revert RWAErrors.AssetAlreadyRegistered(asset);

        DataTypes.Pool memory pool = POOL_MANAGER.getPool(asset);
        if (!pool.isActive) revert RWAErrors.UnderlyingPoolNotActive(asset);
        if (!pool.isCollateralEnabled) revert RWAErrors.UnderlyingPoolCollateralDisabled(asset);
        _validateAgainstPool(asset, params, pool);

        _assets[asset] = AssetConfig({
            status: AssetStatus.Active,
            underlyingPool: asset,
            ltvBps: params.ltvBps,
            maxLtvWithScoreBps: params.maxLtvWithScoreBps,
            liquidationThresholdBps: params.liquidationThresholdBps,
            liquidationBonusBps: params.liquidationBonusBps,
            collateralCap: params.collateralCap,
            oracle: params.oracle,
            maxOracleStalenessSeconds: params.maxOracleStalenessSeconds,
            lastPriceVerifiedTimestamp: 0,
            isCVA: params.isCVA
        });

        emit AssetRegistered(asset, params.oracle, params.ltvBps);
        emit AssetStatusChanged(asset, AssetStatus.Unregistered, AssetStatus.Active);
    }

    /// @notice Updates a registered, non-delisted asset's risk/cap/CVA
    /// parameters (not its oracle, see `setOracleConfig`, and not its
    /// status, see `setAssetStatus`). Allowed on a Frozen asset (e.g. to
    /// correct a cap while frozen) but never on a Delisted one — per
    /// the task's "do not silently delete or invalidate existing
    /// collateral accounting" instruction, a Delisted asset's
    /// configuration is frozen in place as a historical record rather
    /// than editable.
    function updateAssetConfig(address asset, AssetConfigParams calldata params)
        external
        onlyRole(ACCESS_MANAGER.RWA_ADMIN_ROLE())
    {
        AssetConfig storage cfg = _assets[asset];
        if (cfg.status == AssetStatus.Unregistered) revert RWAErrors.AssetNotRegistered(asset);
        if (cfg.status == AssetStatus.Delisted) revert RWAErrors.AssetDelisted(asset);
        if (params.oracle == address(0)) revert RWAErrors.ZeroAddress();

        DataTypes.Pool memory pool = POOL_MANAGER.getPool(asset);
        _validateAgainstPool(asset, params, pool);

        cfg.ltvBps = params.ltvBps;
        cfg.maxLtvWithScoreBps = params.maxLtvWithScoreBps;
        cfg.liquidationThresholdBps = params.liquidationThresholdBps;
        cfg.liquidationBonusBps = params.liquidationBonusBps;
        cfg.collateralCap = params.collateralCap;
        cfg.oracle = params.oracle;
        cfg.maxOracleStalenessSeconds = params.maxOracleStalenessSeconds;
        cfg.isCVA = params.isCVA;

        emit AssetConfigUpdated(asset);
    }

    /// @notice Transitions `asset`'s status. Valid transitions:
    /// Active <-> Frozen (freely, either direction), Active -> Delisted,
    /// Frozen -> Delisted. Delisted is terminal — no transition out of
    /// it exists, matching docs/rwa-market-specification.md §12's
    /// conclusion that a delisted asset is never silently reused;
    /// existing collateral/debt accounting for already-open positions
    /// is entirely unaffected by this call (that accounting lives in
    /// BitVLendingManager, untouched here) and continues to be
    /// manageable via repayment/withdrawal/liquidation exactly as
    /// docs/rwa-market-specification.md §12's table requires — see
    /// docs/rwa-market-implementation.md for the exact limitation this
    /// implies for liquidation once an asset's oracle is also gone.
    function setAssetStatus(address asset, AssetStatus newStatus) external onlyRole(ACCESS_MANAGER.RWA_ADMIN_ROLE()) {
        AssetConfig storage cfg = _assets[asset];
        AssetStatus oldStatus = cfg.status;
        if (oldStatus == AssetStatus.Unregistered) revert RWAErrors.AssetNotRegistered(asset);
        if (oldStatus == AssetStatus.Delisted) revert RWAErrors.AssetDelisted(asset);
        if (newStatus == AssetStatus.Unregistered) {
            revert RWAErrors.InvalidStatusTransition(uint8(oldStatus), uint8(newStatus));
        }
        if (newStatus == oldStatus) revert RWAErrors.InvalidStatusTransition(uint8(oldStatus), uint8(newStatus));

        cfg.status = newStatus;
        emit AssetStatusChanged(asset, oldStatus, newStatus);
    }

    function setCollateralCap(address asset, uint256 cap) external onlyRole(ACCESS_MANAGER.RWA_ADMIN_ROLE()) {
        AssetConfig storage cfg = _assets[asset];
        if (cfg.status == AssetStatus.Unregistered) revert RWAErrors.AssetNotRegistered(asset);
        cfg.collateralCap = cap;
        emit CollateralCapSet(asset, cap);
    }

    /// @notice Restricts (or unrestricts) which debt assets `asset`'s
    /// collateral may be borrowed against. An asset with an empty
    /// allowed-set has no restriction (every debt asset is allowed) —
    /// this function only ever narrows what's otherwise permitted.
    function setAllowedDebtAsset(address asset, address debtAsset, bool allowed)
        external
        onlyRole(ACCESS_MANAGER.RWA_ADMIN_ROLE())
    {
        AssetConfig storage cfg = _assets[asset];
        if (cfg.status == AssetStatus.Unregistered) revert RWAErrors.AssetNotRegistered(asset);
        if (debtAsset == address(0)) revert RWAErrors.ZeroAddress();

        if (allowed) {
            _allowedDebtAssets[asset].add(debtAsset);
        } else {
            _allowedDebtAssets[asset].remove(debtAsset);
        }
        emit AllowedDebtAssetSet(asset, debtAsset, allowed);
    }

    // ── Oracle configuration & staleness attestation (ORACLE_MANAGER_ROLE) ──

    function setOracleConfig(address asset, address oracle, uint32 maxStalenessSeconds)
        external
        onlyRole(ACCESS_MANAGER.ORACLE_MANAGER_ROLE())
    {
        AssetConfig storage cfg = _assets[asset];
        if (cfg.status == AssetStatus.Unregistered) revert RWAErrors.AssetNotRegistered(asset);
        if (oracle == address(0)) revert RWAErrors.ZeroAddress();

        cfg.oracle = oracle;
        cfg.maxOracleStalenessSeconds = maxStalenessSeconds;
        // A newly-configured oracle has no freshness attestation yet —
        // require an explicit markPriceFresh call before this asset can
        // count toward new borrowing capacity again, rather than
        // silently trusting an unverified new source.
        cfg.lastPriceVerifiedTimestamp = 0;
        emit OracleConfigSet(asset, oracle, maxStalenessSeconds);
    }

    /// @notice Reuses IPriceOracle exactly as-is (no new oracle
    /// functionality is invented) to confirm `asset`'s current price is
    /// nonzero, then stamps the current time as this registry's own
    /// freshness attestation — the registry-side staleness tracking
    /// docs/rwa-market-specification.md §8 calls for, layered on top of
    /// (not a change to) the existing read-only IPriceOracle interface,
    /// since that interface has no timestamp field of its own to reuse.
    function markPriceFresh(address asset) external onlyRole(ACCESS_MANAGER.ORACLE_MANAGER_ROLE()) {
        AssetConfig storage cfg = _assets[asset];
        if (cfg.status == AssetStatus.Unregistered) revert RWAErrors.AssetNotRegistered(asset);

        (uint256 price, uint8 priceDecimals) = IPriceOracle(cfg.oracle).getPrice(asset);
        if (price == 0) revert RWAErrors.InvalidOraclePrice(asset);

        cfg.lastPriceVerifiedTimestamp = uint40(block.timestamp);
        emit PriceMarkedFresh(asset, price, priceDecimals);
    }

    // ── IRWACollateralRegistry (BitVLendingManager-facing) ──────────────

    function isRegisteredAsset(address asset) external view returns (bool) {
        return _assets[asset].status != AssetStatus.Unregistered;
    }

    function isEligibleForNewActivity(address asset) external view returns (bool) {
        AssetConfig storage cfg = _assets[asset];
        if (cfg.status != AssetStatus.Active) return false;
        if (cfg.lastPriceVerifiedTimestamp == 0) return false;
        if (block.timestamp - uint256(cfg.lastPriceVerifiedTimestamp) > uint256(cfg.maxOracleStalenessSeconds)) {
            return false;
        }

        // Zero price handling: even between attestations, a live
        // zero/invalid price must never count as eligible — the
        // staleness timestamp alone isn't sufficient, since the price
        // could have gone to zero after being marked fresh.
        (uint256 price,) = IPriceOracle(cfg.oracle).getPrice(asset);
        return price != 0;
    }

    function isDebtAssetAllowed(address asset, address debtAsset) external view returns (bool) {
        EnumerableSet.AddressSet storage allowed = _allowedDebtAssets[asset];
        if (allowed.length() == 0) return true; // no restriction configured
        return allowed.contains(debtAsset);
    }

    function getCollateralCap(address asset) external view returns (uint256) {
        return _assets[asset].collateralCap;
    }

    // ── Other views ──────────────────────────────────────────────────

    function getAssetConfig(address asset) external view returns (AssetConfig memory) {
        return _assets[asset];
    }

    function getAllowedDebtAssets(address asset) external view returns (address[] memory) {
        return _allowedDebtAssets[asset].values();
    }

    // ── Internal ─────────────────────────────────────────────────────

    /// @dev Every registry risk field must be <= the underlying pool's
    /// own configured value — the registry can only ever be equally or
    /// more conservative than the pool's hard configuration, never
    /// grant more favorable terms. This is what makes "registry maximum"
    /// a genuine additional ceiling (docs/rwa-market-specification.md
    /// §9's four-layer bound) rather than a value that could silently
    /// exceed the pool's own hard limit.
    function _validateAgainstPool(address asset, AssetConfigParams calldata params, DataTypes.Pool memory pool)
        internal
        pure
    {
        if (
            params.ltvBps > pool.ltvBps || params.maxLtvWithScoreBps > pool.maxLtvWithScoreBps
                || params.liquidationThresholdBps > pool.liquidationThresholdBps
                || params.liquidationBonusBps > pool.liquidationBonusBps
        ) {
            revert RWAErrors.RiskParamsExceedPoolLimits(asset);
        }
        if (params.ltvBps > params.maxLtvWithScoreBps || params.maxLtvWithScoreBps > params.liquidationThresholdBps) {
            revert RWAErrors.InvalidRiskParams();
        }
    }
}
