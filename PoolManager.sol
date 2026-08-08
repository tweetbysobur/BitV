// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { BaseModule } from "./BaseModule.sol";
import { BitVReceiptToken } from "./BitVReceiptToken.sol";
import { IPoolManager } from "../interfaces/IPoolManager.sol";
import { IAccessManager } from "../interfaces/IAccessManager.sol";
import { IIdentityOracle } from "../interfaces/IIdentityOracle.sol";
import { IInterestRateModel } from "../interfaces/IInterestRateModel.sol";
import { DataTypes } from "../libraries/DataTypes.sol";
import { WadRayMath } from "../libraries/WadRayMath.sol";
import { InterestMath } from "../libraries/InterestMath.sol";
import { PercentageMath } from "../libraries/PercentageMath.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title PoolManager
/// @notice Single-asset liquidity pools. Owns BOTH the supply side
///         (liquidity index, custody of underlying tokens) and pool-level
///         debt accounting (borrow index, `totalScaledDebt`) — see
///         `IPoolManager` and the NatSpec on `DataTypes.Pool` for why both
///         indices are unified in this one contract rather than split
///         against `LendingManager`.
/// @dev Reserve accrual is now EXACT, not modeled: `_accrue` computes the
///      real debt-value delta (`newDebtValue - oldDebtValue`, both derived
///      from the same `totalScaledDebt` before/after the index moves) and
///      takes the reserve's cut from that real number, because there is only
///      one borrow index in the system for it to read.
/// @custom:storage-location erc7201:bitv.storage.PoolManager
contract PoolManager is BaseModule, IPoolManager {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    bytes32 public constant LENDING_MANAGER_ROLE = keccak256("LENDING_MANAGER_ROLE");

    /// @dev No separate `scaledBalances` mapping: `BitVReceiptToken.balanceOf`
    ///      IS the scaled balance, and is the sole source of truth for it.
    ///      An earlier draft kept a parallel internal ledger alongside the
    ///      receipt token's own ERC20 balance — a real bug, not a style
    ///      choice: the two would desync the instant a user transferred
    ///      their receipt token, since a standard ERC20 `transfer` updates
    ///      only the token's own balance mapping, silently orphaning
    ///      whatever the internal mapping still claimed. Reading through the
    ///      token everywhere is what makes receipt-token transfers a correct,
    ///      first-class way to move a supply position, not a mechanism this
    ///      contract would need to explicitly hook and forbid.
    struct PoolManagerStorage {
        mapping(address asset => DataTypes.Pool) pools;
    }

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("bitv.storage.PoolManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0xb32e01d05f77fd07142fc55835336bc0b6ceb97e495d4e18962c9a05e89d1800;

    function _s() private pure returns (PoolManagerStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    modifier poolExists(address asset) {
        if (_s().pools[asset].asset == address(0)) revert Errors.MarketNotFound(_marketId(asset));
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address registry_, address admin) external initializer {
        __BaseModule_init(registry_, admin);
    }

    // ── Pool creation & configuration ────────────────────────────────────

    function createPool(
        address asset,
        address rateModel,
        uint16 reserveFactorBps,
        uint128 supplyCap,
        address validatorPool
    ) external onlyRole(GOVERNANCE_ROLE) returns (address aToken) {
        if (asset == address(0) || rateModel == address(0)) revert Errors.ZeroAddress();
        if (_s().pools[asset].asset != address(0)) {
            revert Errors.AssetAlreadyListed(asset);
        }
        if (reserveFactorBps > PercentageMath.BPS_DENOMINATOR) {
            revert Errors.InvalidBps(reserveFactorBps);
        }

        string memory underlyingSymbol = IERC20Metadata(asset).symbol();
        BitVReceiptToken receiptToken = new BitVReceiptToken(
            address(this),
            asset,
            string.concat("BitV ", underlyingSymbol),
            string.concat("bv", underlyingSymbol)
        );
        aToken = address(receiptToken);

        _s().pools[asset] = DataTypes.Pool({
            asset: asset,
            aToken: aToken,
            liquidityIndexRay: uint128(WadRayMath.RAY),
            borrowIndexRay: uint128(WadRayMath.RAY),
            totalScaledSupply: 0,
            totalScaledDebt: 0,
            supplyCap: supplyCap,
            lastUpdateTimestamp: uint40(block.timestamp),
            reserveFactorBps: reserveFactorBps,
            rateModel: rateModel,
            isPaused: false,
            isFrozen: false,
            isBorrowingEnabled: true,
            validatorPool: validatorPool
        });

        emit PoolCreated(asset, aToken, rateModel);
        if (validatorPool != address(0)) emit ValidatorPoolSet(asset, validatorPool);
    }

    function setPoolState(address asset, bool isPaused, bool isFrozen, bool isBorrowingEnabled)
        external
        onlyRole(GOVERNANCE_ROLE)
        poolExists(asset)
    {
        DataTypes.Pool storage pool = _s().pools[asset];
        pool.isPaused = isPaused;
        pool.isFrozen = isFrozen;
        pool.isBorrowingEnabled = isBorrowingEnabled;
        emit PoolStateUpdated(asset, isPaused, isFrozen, isBorrowingEnabled);
    }

    function setValidatorPool(address asset, address validatorPool)
        external
        onlyRole(GOVERNANCE_ROLE)
        poolExists(asset)
    {
        _s().pools[asset].validatorPool = validatorPool;
        emit ValidatorPoolSet(asset, validatorPool);
    }

    // ── Supply / withdraw ────────────────────────────────────────────────

    function supply(address asset, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        poolExists(asset)
    {
        if (amount == 0) revert Errors.ZeroAmount();

        DataTypes.Pool storage pool = _s().pools[asset];
        if (pool.isPaused) revert Errors.MarketPaused(_marketId(asset));
        if (pool.isFrozen) revert Errors.MarketFrozen(_marketId(asset));

        _checkPoolAccess(pool, msg.sender);

        _accrue(asset);

        if (pool.supplyCap != 0) {
            uint256 newTotal = _totalSuppliedUnderlying(pool) + amount;
            if (newTotal > pool.supplyCap) {
                revert Errors.AmountExceedsBalance(newTotal, pool.supplyCap);
            }
        }

        uint256 scaledAmount = amount.rayDiv(pool.liquidityIndexRay);
        pool.totalScaledSupply += uint128(scaledAmount);

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        BitVReceiptToken(pool.aToken).mint(msg.sender, scaledAmount);

        emit Supplied(asset, msg.sender, amount, scaledAmount);
    }

    function withdraw(address asset, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        poolExists(asset)
        returns (uint256 withdrawn)
    {
        DataTypes.Pool storage pool = _s().pools[asset];
        if (pool.isPaused) revert Errors.MarketPaused(_marketId(asset));

        _accrue(asset);

        uint256 currentBalance = _underlyingBalance(pool, msg.sender);
        withdrawn = amount == type(uint256).max ? currentBalance : amount;

        if (withdrawn == 0) revert Errors.ZeroAmount();
        if (withdrawn > currentBalance) {
            revert Errors.AmountExceedsBalance(withdrawn, currentBalance);
        }

        uint256 available = availableLiquidity(asset);
        if (withdrawn > available) {
            revert Errors.AmountExceedsAvailableLiquidity(withdrawn, available);
        }

        uint256 scaledAmount = withdrawn.rayDiv(pool.liquidityIndexRay);
        pool.totalScaledSupply -= uint128(scaledAmount);

        BitVReceiptToken(pool.aToken).burn(msg.sender, scaledAmount);
        IERC20(asset).safeTransfer(msg.sender, withdrawn);

        emit Withdrawn(asset, msg.sender, withdrawn, scaledAmount);
    }

    // ── LendingManager-restricted liquidity movement ────────────────────

    function borrowFromPool(address asset, uint256 amount, address to)
        external
        onlyRole(LENDING_MANAGER_ROLE)
        whenNotPaused
        nonReentrant
        poolExists(asset)
        returns (uint256 scaledAmount)
    {
        DataTypes.Pool storage pool = _s().pools[asset];
        if (pool.isPaused) revert Errors.MarketPaused(_marketId(asset));
        if (!pool.isBorrowingEnabled) revert Errors.MarketFrozen(_marketId(asset));

        _accrue(asset);

        uint256 available = availableLiquidity(asset);
        if (amount > available) {
            revert Errors.AmountExceedsAvailableLiquidity(amount, available);
        }

        // Scaled at the index `_accrue` just brought current — the caller
        // applies this exact returned value to the borrower's own position,
        // see `IPoolManager.borrowFromPool`.
        scaledAmount = amount.rayDiv(pool.borrowIndexRay);
        pool.totalScaledDebt += uint128(scaledAmount);

        IERC20(asset).safeTransfer(to, amount);
    }

    function notifyRepay(address asset, uint256 amount)
        external
        onlyRole(LENDING_MANAGER_ROLE)
        nonReentrant
        poolExists(asset)
        returns (uint256 scaledAmount)
    {
        DataTypes.Pool storage pool = _s().pools[asset];
        _accrue(asset);

        // LendingManager has already pulled `amount` from the repayer and
        // approved this contract; the transfer happens here so PoolManager
        // — the sole custodian of underlying liquidity — is the only
        // contract that ever moves tokens into or out of its own balance.
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        scaledAmount = amount.rayDiv(pool.borrowIndexRay);
        pool.totalScaledDebt =
            scaledAmount > pool.totalScaledDebt ? 0 : pool.totalScaledDebt - uint128(scaledAmount);
    }

    // ── Interest accrual ─────────────────────────────────────────────────

    function accrueInterest(address asset) public poolExists(asset) {
        _accrue(asset);
    }

    function _accrue(address asset) internal {
        DataTypes.Pool storage pool = _s().pools[asset];
        uint256 elapsed = block.timestamp - pool.lastUpdateTimestamp;
        if (elapsed == 0) return;

        uint256 suppliedUnderlying = _totalSuppliedUnderlying(pool);
        uint256 debtBefore = uint256(pool.totalScaledDebt).rayMul(pool.borrowIndexRay);

        (uint256 borrowRateRay, uint256 supplyRateRay) =
            IInterestRateModel(pool.rateModel).getRates(suppliedUnderlying, debtBefore);

        uint256 borrowCompoundRay =
            InterestMath.calculateCompoundedInterest(InterestMath.toRatePerSecond(borrowRateRay), elapsed);
        uint256 supplyCompoundRay =
            InterestMath.calculateCompoundedInterest(InterestMath.toRatePerSecond(supplyRateRay), elapsed);

        // Both indices advance together, over the identical elapsed window,
        // from the identical rate-model call above — this is the fix for the
        // drift documented in `docs/contracts-architecture.md` §Known issues:
        // there is exactly one accrual computation per market per call,
        // never two independently-triggered ones.
        pool.borrowIndexRay =
            uint128(InterestMath.accrueIndex(pool.borrowIndexRay, borrowCompoundRay));
        pool.liquidityIndexRay =
            uint128(InterestMath.accrueIndex(pool.liquidityIndexRay, supplyCompoundRay));
        pool.lastUpdateTimestamp = uint40(block.timestamp);

        emit InterestAccrued(asset, pool.liquidityIndexRay, pool.borrowIndexRay, supplyRateRay);

        // Reserve cut, taken from the EXACT debt-value delta this accrual
        // just produced — `debtAfter` is derived from the same
        // `totalScaledDebt` the pool already holds, scaled at the
        // just-updated index, not a second independent estimate.
        uint256 debtAfter = uint256(pool.totalScaledDebt).rayMul(pool.borrowIndexRay);
        uint256 reserveShareUnderlying =
            (debtAfter - debtBefore).percentMul(pool.reserveFactorBps);

        if (reserveShareUnderlying > 0) {
            address treasury = registry().getAddress(registry().TREASURY());
            if (treasury != address(0)) {
                uint256 scaledReserveMint = reserveShareUnderlying.rayDiv(pool.liquidityIndexRay);
                pool.totalScaledSupply += uint128(scaledReserveMint);
                BitVReceiptToken(pool.aToken).mint(treasury, scaledReserveMint);
            }
        }
    }

    // ── Access gating ────────────────────────────────────────────────────

    /// @dev Two independent layers, both consulted: the protocol-wide
    ///      `AccessLending` capability (bound to a general BitV Validator
    ///      pool via `AccessManager.setCapabilityRequirement`, or ungated
    ///      until governance configures one) — see `docs/contracts-architecture.md`
    ///      §Permission layer for why supply/withdraw is gated on this
    ///      capability specifically rather than `JoinLiquidityPools` — and
    ///      this SPECIFIC pool's own `validatorPool`, for markets requiring
    ///      stricter, market-specific eligibility (e.g. an institution-only
    ///      market) beyond the protocol-wide baseline.
    function _checkPoolAccess(DataTypes.Pool storage pool, address account) internal view {
        IAccessManager accessManager =
            IAccessManager(registry().requireAddress(registry().ACCESS_MANAGER()));
        accessManager.requireCapability(IAccessManager.Capability.AccessLending, account);

        if (pool.validatorPool != address(0)) {
            IIdentityOracle oracle =
                IIdentityOracle(registry().requireAddress(registry().IDENTITY_ORACLE()));
            if (!oracle.isEligibleForPool(pool.validatorPool, account)) {
                revert Errors.IdentityIneligible(account, uint8(oracle.statusOf(account)));
            }
        }
    }

    // ── Views ────────────────────────────────────────────────────────────

    function getPool(address asset) external view returns (DataTypes.Pool memory) {
        return _s().pools[asset];
    }

    function getUtilization(address asset) external view returns (uint256) {
        DataTypes.Pool storage pool = _s().pools[asset];
        uint256 supplied = _totalSuppliedUnderlying(pool);
        return IInterestRateModel(pool.rateModel).getUtilization(supplied, _totalBorrowed(pool));
    }

    function getCurrentRates(address asset)
        external
        view
        returns (uint256 borrowRateRay, uint256 supplyRateRay)
    {
        DataTypes.Pool storage pool = _s().pools[asset];
        uint256 supplied = _totalSuppliedUnderlying(pool);
        return IInterestRateModel(pool.rateModel).getRates(supplied, _totalBorrowed(pool));
    }

    function totalBorrowed(address asset) external view returns (uint256) {
        return _totalBorrowed(_s().pools[asset]);
    }

    /// @dev `view`-safe projection — mirrors `_accrue`'s math exactly but
    ///      writes nothing, so `LendingManager`'s `view` functions can show
    ///      an up-to-the-second figure without needing a mutating call.
    function previewAccruedIndices(address asset)
        external
        view
        returns (uint256 liquidityIndexRay, uint256 borrowIndexRay)
    {
        DataTypes.Pool storage pool = _s().pools[asset];
        uint256 elapsed = block.timestamp - pool.lastUpdateTimestamp;
        if (elapsed == 0) return (pool.liquidityIndexRay, pool.borrowIndexRay);

        uint256 supplied = _totalSuppliedUnderlying(pool);
        uint256 debt = _totalBorrowed(pool);
        (uint256 borrowRateRay, uint256 supplyRateRay) =
            IInterestRateModel(pool.rateModel).getRates(supplied, debt);

        uint256 borrowCompoundRay =
            InterestMath.calculateCompoundedInterest(InterestMath.toRatePerSecond(borrowRateRay), elapsed);
        uint256 supplyCompoundRay =
            InterestMath.calculateCompoundedInterest(InterestMath.toRatePerSecond(supplyRateRay), elapsed);

        liquidityIndexRay = InterestMath.accrueIndex(pool.liquidityIndexRay, supplyCompoundRay);
        borrowIndexRay = InterestMath.accrueIndex(pool.borrowIndexRay, borrowCompoundRay);
    }

    function balanceOf(address asset, address account) external view returns (uint256) {
        return _underlyingBalance(_s().pools[asset], account);
    }

    function totalLiquidity(address asset) external view returns (uint256) {
        return _totalSuppliedUnderlying(_s().pools[asset]);
    }

    function availableLiquidity(address asset) public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function _totalSuppliedUnderlying(DataTypes.Pool storage pool) internal view returns (uint256) {
        return uint256(pool.totalScaledSupply).rayMul(pool.liquidityIndexRay);
    }

    function _totalBorrowed(DataTypes.Pool storage pool) internal view returns (uint256) {
        return uint256(pool.totalScaledDebt).rayMul(pool.borrowIndexRay);
    }

    function _underlyingBalance(DataTypes.Pool storage pool, address account)
        internal
        view
        returns (uint256)
    {
        uint256 scaledBalance = BitVReceiptToken(pool.aToken).balanceOf(account);
        return scaledBalance.rayMul(pool.liquidityIndexRay);
    }

    function _marketId(address asset) internal pure returns (bytes32) {
        return keccak256(abi.encode(asset));
    }
}
