// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {BitVComplianceGuard} from "../compliance/BitVComplianceGuard.sol";
import {BitVRoleConsumer} from "../access/BitVRoleConsumer.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {ProtocolErrors} from "../libraries/ProtocolErrors.sol";
import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";

/**
 * @title BitVPoolManager
 * @notice Identity-gated, permissioned liquidity pool. One pool per
 * underlying asset. Suppliers earn interest via a ray-scaled balance
 * (like Aave's aToken model, tracked here directly rather than via a
 * separate receipt-token contract — see `balanceOf`). Borrowing is only
 * ever initiated by the registered BitVLendingManager, which owns
 * collateral/health-factor logic; this contract owns pool-level
 * liquidity accounting only.
 *
 * Real on-chain balances only — no off-chain or synthetic accounting.
 */
contract BitVPoolManager is BitVComplianceGuard, BitVRoleConsumer, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;

    mapping(address asset => DataTypes.Pool) private _pools;
    mapping(address asset => mapping(address user => uint256)) private _scaledSupply;

    address public lendingManager;
    address public immutable TREASURY;

    event PoolCreated(address indexed asset);
    event PoolConfigUpdated(address indexed asset);
    event PoolPausedSet(address indexed asset, bool isPaused);
    event LendingManagerSet(address indexed lendingManager);
    event Deposited(address indexed asset, address indexed user, uint256 amount, uint256 scaledAmount);
    event Withdrawn(address indexed asset, address indexed user, uint256 amount, uint256 scaledAmount);
    event BorrowedFromPool(address indexed asset, address indexed to, uint256 amount, uint256 scaledAmount);
    event RepaidToPool(address indexed asset, uint256 amount, uint256 scaledAmount);
    event InterestAccrued(address indexed asset, uint256 liquidityIndexRay, uint256 borrowIndexRay);
    event ReserveClaimed(address indexed asset, uint256 amount, uint256 scaledAmount);

    struct PoolConfigParams {
        uint16 ltvBps;
        uint16 maxLtvWithScoreBps; // Build 04: BitScore's absolute LTV ceiling for this asset; pass equal to ltvBps for "no bonus possible"
        uint16 liquidationThresholdBps;
        uint16 liquidationBonusBps;
        uint16 reserveFactorBps;
        uint256 supplyCap;
        uint256 borrowCap;
        address interestRateModel;
        address priceOracle;
        bool isBorrowingEnabled;
        bool isCollateralEnabled;
    }

    modifier onlyLendingManager() {
        if (msg.sender != lendingManager) revert ProtocolErrors.CallerNotLendingManager();
        _;
    }

    modifier poolActive(address asset) {
        DataTypes.Pool storage pool = _pools[asset];
        if (!pool.isActive) revert ProtocolErrors.PoolNotActive(asset);
        if (pool.isPaused) revert ProtocolErrors.PoolIsPaused(asset);
        _;
    }

    constructor(address complianceValidator, address owner_, address accessManager, address treasury_)
        BitVComplianceGuard(complianceValidator, owner_)
        BitVRoleConsumer(accessManager)
    {
        if (treasury_ == address(0)) revert ProtocolErrors.ZeroAddress();
        TREASURY = treasury_;
    }

    // ── Admin: pool creation & configuration ────────────────────────────

    function createPool(address asset, PoolConfigParams calldata cfg) external onlyRole(ACCESS_MANAGER.PROTOCOL_ADMIN_ROLE()) {
        if (_pools[asset].isActive) revert ProtocolErrors.PoolAlreadyExists(asset);
        _validateRiskParams(cfg.ltvBps, cfg.maxLtvWithScoreBps, cfg.liquidationThresholdBps, cfg.liquidationBonusBps);

        _pools[asset] = DataTypes.Pool({
            isActive: true,
            isPaused: false,
            isBorrowingEnabled: cfg.isBorrowingEnabled,
            isCollateralEnabled: cfg.isCollateralEnabled,
            ltvBps: cfg.ltvBps,
            maxLtvWithScoreBps: cfg.maxLtvWithScoreBps,
            liquidationThresholdBps: cfg.liquidationThresholdBps,
            liquidationBonusBps: cfg.liquidationBonusBps,
            reserveFactorBps: cfg.reserveFactorBps,
            supplyCap: cfg.supplyCap,
            borrowCap: cfg.borrowCap,
            totalScaledSupply: 0,
            totalScaledDebt: 0,
            liquidityIndexRay: WadRayMath.RAY,
            borrowIndexRay: WadRayMath.RAY,
            lastUpdateTimestamp: uint40(block.timestamp),
            interestRateModel: cfg.interestRateModel,
            priceOracle: cfg.priceOracle
        });

        emit PoolCreated(asset);
    }

    function setLendingManager(address lendingManager_) external onlyRole(ACCESS_MANAGER.PROTOCOL_ADMIN_ROLE()) {
        if (lendingManager_ == address(0)) revert ProtocolErrors.ZeroAddress();
        lendingManager = lendingManager_;
        emit LendingManagerSet(lendingManager_);
    }

    function setPoolPaused(address asset, bool paused) external onlyRole(ACCESS_MANAGER.PAUSER_ROLE()) {
        _pools[asset].isPaused = paused;
        emit PoolPausedSet(asset, paused);
    }

    function setBorrowingAndCollateralEnabled(address asset, bool borrowingEnabled, bool collateralEnabled)
        external
        onlyRole(ACCESS_MANAGER.POOL_MANAGER_ROLE())
    {
        DataTypes.Pool storage pool = _pools[asset];
        if (!pool.isActive) revert ProtocolErrors.PoolNotActive(asset);
        pool.isBorrowingEnabled = borrowingEnabled;
        pool.isCollateralEnabled = collateralEnabled;
        emit PoolConfigUpdated(asset);
    }

    function setRiskParams(
        address asset,
        uint16 ltvBps,
        uint16 maxLtvWithScoreBps,
        uint16 liquidationThresholdBps,
        uint16 liquidationBonusBps
    ) external onlyRole(ACCESS_MANAGER.RISK_MANAGER_ROLE()) {
        _validateRiskParams(ltvBps, maxLtvWithScoreBps, liquidationThresholdBps, liquidationBonusBps);
        DataTypes.Pool storage pool = _pools[asset];
        if (!pool.isActive) revert ProtocolErrors.PoolNotActive(asset);
        pool.ltvBps = ltvBps;
        pool.maxLtvWithScoreBps = maxLtvWithScoreBps;
        pool.liquidationThresholdBps = liquidationThresholdBps;
        pool.liquidationBonusBps = liquidationBonusBps;
        emit PoolConfigUpdated(asset);
    }

    function setCaps(address asset, uint256 supplyCap, uint256 borrowCap) external onlyRole(ACCESS_MANAGER.RISK_MANAGER_ROLE()) {
        DataTypes.Pool storage pool = _pools[asset];
        if (!pool.isActive) revert ProtocolErrors.PoolNotActive(asset);
        pool.supplyCap = supplyCap;
        pool.borrowCap = borrowCap;
        emit PoolConfigUpdated(asset);
    }

    function setReserveFactor(address asset, uint16 reserveFactorBps) external onlyRole(ACCESS_MANAGER.RISK_MANAGER_ROLE()) {
        if (reserveFactorBps > 10_000) revert ProtocolErrors.InvalidRiskParams();
        DataTypes.Pool storage pool = _pools[asset];
        if (!pool.isActive) revert ProtocolErrors.PoolNotActive(asset);
        pool.reserveFactorBps = reserveFactorBps;
        emit PoolConfigUpdated(asset);
    }

    function setInterestRateModel(address asset, address model) external onlyRole(ACCESS_MANAGER.RISK_MANAGER_ROLE()) {
        DataTypes.Pool storage pool = _pools[asset];
        if (!pool.isActive) revert ProtocolErrors.PoolNotActive(asset);
        accrueInterest(asset);
        pool.interestRateModel = model;
        emit PoolConfigUpdated(asset);
    }

    function setPriceOracle(address asset, address oracle) external onlyRole(ACCESS_MANAGER.RISK_MANAGER_ROLE()) {
        DataTypes.Pool storage pool = _pools[asset];
        if (!pool.isActive) revert ProtocolErrors.PoolNotActive(asset);
        pool.priceOracle = oracle;
        emit PoolConfigUpdated(asset);
    }

    function _validateRiskParams(
        uint16 ltvBps,
        uint16 maxLtvWithScoreBps,
        uint16 liquidationThresholdBps,
        uint16 liquidationBonusBps
    ) internal pure {
        // LTV must leave room below the liquidation threshold, which
        // itself must leave room for the liquidation bonus without
        // guaranteeing bad debt on every liquidation.
        if (ltvBps > liquidationThresholdBps) revert ProtocolErrors.InvalidRiskParams();
        if (liquidationThresholdBps >= 10_000) revert ProtocolErrors.InvalidRiskParams();
        // Build 04: BitScore's absolute LTV ceiling must sit between the
        // base LTV and the liquidation threshold — it can never be lower
        // than the base (that would make "the bonus" a penalty by
        // construction) and never exceed the threshold (that would let a
        // score-boosted position start life already liquidatable).
        if (maxLtvWithScoreBps < ltvBps || maxLtvWithScoreBps > liquidationThresholdBps) {
            revert ProtocolErrors.InvalidRiskParams();
        }
        // A bonus that pushes seized value above 100% of collateral at the
        // threshold boundary is a known, documented bad-debt tradeoff (see
        // docs/protocol-architecture.md) — allowed, but capped so it can't
        // be set to something absurd.
        if (liquidationBonusBps > 5_000) revert ProtocolErrors.InvalidRiskParams(); // cap at +50% seize bonus
    }

    // ── Supply side ──────────────────────────────────────────────────────

    function deposit(address asset, uint256 amount) external nonReentrant poolActive(asset) {
        _requireCompliance(msg.sender);
        if (amount == 0) revert ProtocolErrors.ZeroAmount();

        accrueInterest(asset);
        DataTypes.Pool storage pool = _pools[asset];

        uint256 newTotalUnderlying = _totalSuppliedUnderlying(pool) + amount;
        if (pool.supplyCap != 0 && newTotalUnderlying > pool.supplyCap) {
            revert ProtocolErrors.SupplyCapExceeded(newTotalUnderlying, pool.supplyCap);
        }

        uint256 scaledAmount = amount.rayDiv(pool.liquidityIndexRay);
        _scaledSupply[asset][msg.sender] += scaledAmount;
        pool.totalScaledSupply += scaledAmount;

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(asset, msg.sender, amount, scaledAmount);
    }

    function withdraw(address asset, uint256 amount) external nonReentrant poolActive(asset) returns (uint256 withdrawn) {
        _requireCompliance(msg.sender);

        accrueInterest(asset);
        DataTypes.Pool storage pool = _pools[asset];

        uint256 scaledBalance = _scaledSupply[asset][msg.sender];
        uint256 currentBalance = scaledBalance.rayMul(pool.liquidityIndexRay);

        uint256 scaledAmount;
        if (amount == type(uint256).max) {
            // Exact scaled balance, not a round-tripped underlying
            // amount — keeps totalScaledSupply exact on full withdraws.
            scaledAmount = scaledBalance;
            withdrawn = scaledAmount.rayMul(pool.liquidityIndexRay);
        } else {
            withdrawn = amount;
            scaledAmount = withdrawn.rayDiv(pool.liquidityIndexRay);
        }

        if (withdrawn == 0) revert ProtocolErrors.ZeroAmount();
        if (withdrawn > currentBalance) revert ProtocolErrors.AmountExceedsBalance(withdrawn, currentBalance);

        uint256 available = availableLiquidity(asset);
        if (withdrawn > available) revert ProtocolErrors.AmountExceedsAvailableLiquidity(withdrawn, available);

        _scaledSupply[asset][msg.sender] = scaledBalance - scaledAmount;
        pool.totalScaledSupply -= scaledAmount;

        IERC20(asset).safeTransfer(msg.sender, withdrawn);

        emit Withdrawn(asset, msg.sender, withdrawn, scaledAmount);
    }

    /// @notice Lets the protocol treasury realize its own accrued
    /// reserve-factor interest — the scaled-supply balance
    /// `accrueInterest` has been crediting to `TREASURY` all along (see
    /// its NatSpec). Mirrors `withdraw()`'s exact accounting (same
    /// liquidity index, same available-liquidity bound) but is scoped
    /// strictly to `_scaledSupply[asset][TREASURY]` and skips
    /// `_requireCompliance` — this is the protocol claiming interest it
    /// already owns by construction, not a user-facing eligibility
    /// action, so CVI has nothing to check here. Only the treasury
    /// contract itself may call this — never a generic withdraw
    /// surface, and it can never touch any other address's balance.
    function claimReserve(address asset, uint256 amount)
        external
        nonReentrant
        poolActive(asset)
        returns (uint256 claimed)
    {
        if (msg.sender != TREASURY) revert ProtocolErrors.CallerNotTreasury();

        accrueInterest(asset);
        DataTypes.Pool storage pool = _pools[asset];

        uint256 scaledBalance = _scaledSupply[asset][TREASURY];
        uint256 currentBalance = scaledBalance.rayMul(pool.liquidityIndexRay);

        uint256 scaledAmount;
        if (amount == type(uint256).max) {
            scaledAmount = scaledBalance;
            claimed = scaledAmount.rayMul(pool.liquidityIndexRay);
        } else {
            claimed = amount;
            scaledAmount = claimed.rayDiv(pool.liquidityIndexRay);
        }

        if (claimed == 0) revert ProtocolErrors.ZeroAmount();
        if (claimed > currentBalance) revert ProtocolErrors.AmountExceedsBalance(claimed, currentBalance);

        uint256 available = availableLiquidity(asset);
        if (claimed > available) revert ProtocolErrors.AmountExceedsAvailableLiquidity(claimed, available);

        _scaledSupply[asset][TREASURY] = scaledBalance - scaledAmount;
        pool.totalScaledSupply -= scaledAmount;

        IERC20(asset).safeTransfer(TREASURY, claimed);

        emit ReserveClaimed(asset, claimed, scaledAmount);
    }

    // ── LendingManager-restricted liquidity movement ────────────────────

    function borrowFromPool(address asset, uint256 amount, address to)
        external
        nonReentrant
        onlyLendingManager
        poolActive(asset)
        returns (uint256 scaledAmount)
    {
        DataTypes.Pool storage pool = _pools[asset];
        if (!pool.isBorrowingEnabled) revert ProtocolErrors.BorrowingDisabled(asset);
        if (amount == 0) revert ProtocolErrors.ZeroAmount();

        accrueInterest(asset);

        uint256 available = availableLiquidity(asset);
        if (amount > available) revert ProtocolErrors.AmountExceedsAvailableLiquidity(amount, available);

        uint256 newTotalDebt = _totalBorrowedUnderlying(pool) + amount;
        if (pool.borrowCap != 0 && newTotalDebt > pool.borrowCap) {
            revert ProtocolErrors.BorrowCapExceeded(newTotalDebt, pool.borrowCap);
        }

        scaledAmount = amount.rayDiv(pool.borrowIndexRay);
        pool.totalScaledDebt += scaledAmount;

        IERC20(asset).safeTransfer(to, amount);

        emit BorrowedFromPool(asset, to, amount, scaledAmount);
    }

    /// @notice Repays pool-level debt accounting. Assumes `amount` of
    /// `asset` has already been transferred to this contract by the
    /// (trusted, singular, admin-registered) lending manager — see its
    /// NatSpec for why that trust boundary is acceptable here.
    function repayToPool(address asset, uint256 amount) external nonReentrant onlyLendingManager returns (uint256 scaledAmount) {
        if (amount == 0) revert ProtocolErrors.ZeroAmount();

        accrueInterest(asset);
        DataTypes.Pool storage pool = _pools[asset];

        uint256 currentDebt = _totalBorrowedUnderlying(pool);
        uint256 repayAmount = amount > currentDebt ? currentDebt : amount;

        scaledAmount = repayAmount.rayDiv(pool.borrowIndexRay);
        if (scaledAmount > pool.totalScaledDebt) scaledAmount = pool.totalScaledDebt;
        pool.totalScaledDebt -= scaledAmount;

        emit RepaidToPool(asset, repayAmount, scaledAmount);
    }

    // ── Interest accrual ─────────────────────────────────────────────────

    function accrueInterest(address asset) public {
        DataTypes.Pool storage pool = _pools[asset];
        if (!pool.isActive) return;

        uint256 timeDelta = block.timestamp - pool.lastUpdateTimestamp;
        if (timeDelta == 0) return;

        uint256 suppliedUnderlying = _totalSuppliedUnderlying(pool);
        uint256 borrowedUnderlying = _totalBorrowedUnderlying(pool);

        if (pool.interestRateModel != address(0) && borrowedUnderlying > 0) {
            uint256 borrowRateRay =
                IInterestRateModel(pool.interestRateModel).getBorrowRateRay(suppliedUnderlying, borrowedUnderlying);

            // Simple (linear) accrual over the elapsed period — an
            // auditable, deterministic approximation rather than
            // continuous compounding, documented in
            // docs/protocol-architecture.md.
            uint256 borrowInterestFactorRay = borrowRateRay * timeDelta / 365 days;
            uint256 newBorrowIndexRay = pool.borrowIndexRay + pool.borrowIndexRay.rayMul(borrowInterestFactorRay);

            uint256 debtBefore = borrowedUnderlying;
            uint256 debtAfter = pool.totalScaledDebt.rayMul(newBorrowIndexRay);
            uint256 interestAccrued = debtAfter - debtBefore;

            pool.borrowIndexRay = newBorrowIndexRay;

            if (suppliedUnderlying > 0) {
                uint256 supplierShare = interestAccrued - interestAccrued * pool.reserveFactorBps / 10_000;
                uint256 liquidityFactorRay = supplierShare.rayDiv(suppliedUnderlying);
                pool.liquidityIndexRay += pool.liquidityIndexRay.rayMul(liquidityFactorRay);

                uint256 reserveShare = interestAccrued - supplierShare;
                if (reserveShare > 0) {
                    // Reserve share accrues as additional scaled supply
                    // credited to the treasury — same mechanism as a
                    // supplier, so it compounds like everyone else's
                    // deposits rather than needing a separate ledger.
                    uint256 reserveScaledAmount = reserveShare.rayDiv(pool.liquidityIndexRay);
                    _scaledSupply[asset][TREASURY] += reserveScaledAmount;
                    pool.totalScaledSupply += reserveScaledAmount;
                }
            }
        }

        pool.lastUpdateTimestamp = uint40(block.timestamp);
        emit InterestAccrued(asset, pool.liquidityIndexRay, pool.borrowIndexRay);
    }

    // ── Views ────────────────────────────────────────────────────────────

    function getPool(address asset) external view returns (DataTypes.Pool memory) {
        return _pools[asset];
    }

    /// @notice The treasury's currently claimable reserve-factor
    /// interest for `asset` — equivalent to `balanceOf(asset, TREASURY)`,
    /// named explicitly so callers don't have to know the reserve is
    /// tracked via the treasury's ordinary supplier balance.
    function reserveBalance(address asset) external view returns (uint256) {
        return _scaledSupply[asset][TREASURY].rayMul(_pools[asset].liquidityIndexRay);
    }

    function balanceOf(address asset, address user) external view returns (uint256) {
        DataTypes.Pool storage pool = _pools[asset];
        return _scaledSupply[asset][user].rayMul(pool.liquidityIndexRay);
    }

    function scaledBalanceOf(address asset, address user) external view returns (uint256) {
        return _scaledSupply[asset][user];
    }

    function totalSupplied(address asset) public view returns (uint256) {
        return _totalSuppliedUnderlying(_pools[asset]);
    }

    function totalBorrowed(address asset) public view returns (uint256) {
        return _totalBorrowedUnderlying(_pools[asset]);
    }

    function availableLiquidity(address asset) public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function utilizationRay(address asset) external view returns (uint256) {
        uint256 supplied = totalSupplied(asset);
        if (supplied == 0) return 0;
        return totalBorrowed(asset).rayDiv(supplied);
    }

    function getLiquidityIndex(address asset) external view returns (uint256) {
        return _pools[asset].liquidityIndexRay;
    }

    function getBorrowIndex(address asset) external view returns (uint256) {
        return _pools[asset].borrowIndexRay;
    }

    function _totalSuppliedUnderlying(DataTypes.Pool storage pool) internal view returns (uint256) {
        return pool.totalScaledSupply.rayMul(pool.liquidityIndexRay);
    }

    function _totalBorrowedUnderlying(DataTypes.Pool storage pool) internal view returns (uint256) {
        return pool.totalScaledDebt.rayMul(pool.borrowIndexRay);
    }
}
