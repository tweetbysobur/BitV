// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BitVComplianceGuard} from "../compliance/BitVComplianceGuard.sol";
import {BitVRoleConsumer} from "../access/BitVRoleConsumer.sol";
import {BitVTreasury} from "./BitVTreasury.sol";
import {IBitVVaultStrategy} from "../interfaces/IBitVVaultStrategy.sol";
import {VaultErrors} from "../libraries/VaultErrors.sol";

/**
 * @title BitVYieldVault
 * @notice Permissioned ERC-4626 yield vault for one verified underlying
 * asset. Implements docs/yield-vault-specification.md exactly —
 * Cleanverse CVI is the sole eligibility layer (BitScore is
 * deliberately not a dependency, spec §17), vault liquidity is
 * completely independent from BitV's lending pools (spec §16 option A),
 * and vault shares are non-transferable for the MVP so a verified
 * depositor cannot hand shares to an unverified wallet (spec §7).
 *
 * Architecture: this contract owns every accounting decision (ERC-4626
 * shares, compliance, limits, pause, fees). It never lets a strategy
 * influence accounting beyond the plain `totalAssets()` figure the
 * strategy reports — see IBitVVaultStrategy's NatSpec.
 */
contract BitVYieldVault is ERC4626, BitVComplianceGuard, BitVRoleConsumer, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Conservative fixed decimal offset for the ERC-4626
    /// virtual-shares/virtual-assets inflation-attack mitigation
    /// (OpenZeppelin's `_decimalsOffset()` mechanism). 6 is chosen
    /// deliberately over the OpenZeppelin default of 0: it makes the
    /// "donate to the empty vault to skew the price" attack require the
    /// attacker to donate roughly 1,000,000x their own deposit to move
    /// the reported share price by 1 part in a million, matching
    /// OpenZeppelin's own guidance that a non-zero offset is the
    /// recommended mitigation for asset/share decimal mismatches and
    /// first-depositor griefing. See docs/yield-vault-implementation.md
    /// for the worked-through rationale.
    uint8 private constant DECIMALS_OFFSET = 6;

    /// @notice Hard ceiling on the performance fee, enforced in the
    /// setter — no configuration can ever exceed this regardless of who
    /// holds RISK_MANAGER_ROLE. 2,000 bps = 20%.
    uint256 public constant MAX_PERFORMANCE_FEE_BPS = 2_000;

    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @notice Protocol treasury every performance fee flows to. Reuses
    /// the existing BitVTreasury — no second treasury is created.
    address public immutable TREASURY;

    /// @notice The vault's single active strategy, or the zero address
    /// if none is configured (deposits then simply sit idle).
    IBitVVaultStrategy public strategy;

    /// @notice Maximum `totalAssets()` the vault will accept deposits
    /// up to. `type(uint256).max` means effectively uncapped.
    uint256 public vaultCap;

    /// @notice Minimum `assets` amount accepted by `deposit()` (does not
    /// apply to `mint()`, which is instead floored via the resulting
    /// `assets` amount after conversion — see `mint()`'s NatSpec).
    uint256 public minDeposit;

    /// @notice Fraction (bps) of `totalAssets()` the active strategy may
    /// ever hold at once. Re-checked on every allocation, not just at
    /// configuration time. Defaults to 0 (no strategy usage) until
    /// STRATEGY_MANAGER_ROLE explicitly enables it.
    uint256 public maxStrategyAllocationBps;

    /// @notice Fraction (bps) of `totalAssets()` that must remain idle
    /// (not deployed to the strategy) at all times. Defaults to 10,000
    /// (100% idle — no strategy usage) until VAULT_MANAGER_ROLE
    /// explicitly lowers it.
    uint256 public minIdleReserveBps = BPS_DENOMINATOR;

    bool public depositsPaused;
    bool public withdrawalsPaused;
    bool public strategyPaused;

    /// @notice Performance fee, in bps of newly realized profit only
    /// (never of principal). Capped at MAX_PERFORMANCE_FEE_BPS.
    uint256 public performanceFeeBps;

    /// @notice Monotonically non-decreasing peak of `totalAssets()` ever
    /// observed. A performance fee is only ever charged on the portion
    /// of `totalAssets()` that exceeds this prior peak — i.e. recovering
    /// from a loss back up to a previous high is never taxed as if it
    /// were new profit. This is the full extent of this MVP's
    /// high-water-mark logic, deliberately kept to a single monotonic
    /// peak rather than a more elaborate per-depositor scheme (see
    /// docs/yield-vault-specification.md open question 6).
    uint256 public highWaterMarkAssets;

    /// @notice Sum of `feeAssets`/`feeShares` computed at each accrual
    /// event, tracked explicitly rather than re-derived via
    /// `_convertToAssets` at collection time. Re-deriving from
    /// `balanceOf(address(this))` at collection time would self-dilute:
    /// minting fee shares increases `totalSupply()`, so converting those
    /// same shares back to assets afterward (using the now-larger
    /// supply as the denominator) systematically under-values them
    /// relative to the `feeAssets` figure they were minted for. Tracking
    /// the ledger explicitly avoids that rounding trap entirely.
    uint256 public accruedFeeShares;
    uint256 public accruedFeeAssets;

    event StrategySet(address indexed oldStrategy, address indexed newStrategy);
    event StrategyExited(address indexed strategy, uint256 recovered);
    event StrategyAllocated(uint256 amount);
    event StrategyWithdrawn(uint256 amount);
    event StrategyEmergencyExited(address indexed strategy, uint256 recovered);
    event VaultCapSet(uint256 newCap);
    event MinDepositSet(uint256 newMinDeposit);
    event MaxStrategyAllocationBpsSet(uint256 bps);
    event MinIdleReserveBpsSet(uint256 bps);
    event DepositsPausedSet(bool paused);
    event WithdrawalsPausedSet(bool paused);
    event StrategyPausedSet(bool paused);
    event PerformanceFeeBpsSet(uint256 bps);
    event PerformanceFeeAccrued(uint256 profitAssets, uint256 feeAssets, uint256 feeShares);
    event PerformanceFeeCollected(uint256 assets, uint256 shares);
    event EmergencyWithdrawn(address indexed user, uint256 shares, uint256 assetsReturned);

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address complianceValidator,
        address complianceOwner,
        address accessManager,
        address treasury_,
        uint256 vaultCap_,
        uint256 minDeposit_
    )
        ERC20(name_, symbol_)
        ERC4626(asset_)
        BitVComplianceGuard(complianceValidator, complianceOwner)
        BitVRoleConsumer(accessManager)
    {
        if (treasury_ == address(0)) revert VaultErrors.ZeroAddress();
        TREASURY = treasury_;
        vaultCap = vaultCap_;
        minDeposit = minDeposit_;
    }

    // ── ERC-4626 core, overridden for compliance/limits/pause/fees ─────

    function _decimalsOffset() internal pure override returns (uint8) {
        return DECIMALS_OFFSET;
    }

    /// @notice Idle balance plus whatever the active strategy reports —
    /// the only place strategy-reported value enters vault accounting.
    function totalAssets() public view override returns (uint256) {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        uint256 deployed = address(strategy) == address(0) ? 0 : strategy.totalAssets();
        return idle + deployed;
    }

    function maxDeposit(address receiver) public view override returns (uint256) {
        if (depositsPaused) return 0;
        if (!_isCompliant(receiver)) return 0;
        uint256 ta = totalAssets();
        if (ta >= vaultCap) return 0;
        return vaultCap - ta;
    }

    function maxMint(address receiver) public view override returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (maxAssets == 0) return 0;
        return previewDeposit(maxAssets);
    }

    /// @notice Deposits and mints always self-service for the MVP —
    /// `receiver` must equal `msg.sender`. Removes any path where a
    /// compliant caller could mint shares directly to an unverified
    /// address, without needing a second, easy-to-forget compliance
    /// check (spec §7's transfer-bypass concern applies equally here).
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        if (receiver != msg.sender) revert VaultErrors.OnlySelfService();
        if (depositsPaused) revert VaultErrors.DepositsPaused();
        _requireCompliance(msg.sender);
        if (assets < minDeposit) revert VaultErrors.BelowMinimumDeposit(assets, minDeposit);
        _accruePerformanceFee();
        shares = previewDeposit(assets);
        if (shares == 0) revert VaultErrors.ZeroShares();
        shares = super.deposit(assets, receiver);
        _adjustHighWaterMarkForPrincipal(int256(assets));
    }

    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        if (receiver != msg.sender) revert VaultErrors.OnlySelfService();
        if (depositsPaused) revert VaultErrors.DepositsPaused();
        _requireCompliance(msg.sender);
        if (shares == 0) revert VaultErrors.ZeroShares();
        _accruePerformanceFee();
        assets = previewMint(shares);
        if (assets < minDeposit) revert VaultErrors.BelowMinimumDeposit(assets, minDeposit);
        assets = super.mint(shares, receiver);
        _adjustHighWaterMarkForPrincipal(int256(assets));
    }

    function withdraw(uint256 assets, address receiver, address owner_)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (receiver != msg.sender || owner_ != msg.sender) revert VaultErrors.OnlySelfService();
        if (withdrawalsPaused) revert VaultErrors.WithdrawalsPaused();
        _requireCompliance(msg.sender);
        _accruePerformanceFee();
        _ensureLiquidity(assets);
        shares = super.withdraw(assets, receiver, owner_);
        _adjustHighWaterMarkForPrincipal(-int256(assets));
    }

    function redeem(uint256 shares, address receiver, address owner_)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (receiver != msg.sender || owner_ != msg.sender) revert VaultErrors.OnlySelfService();
        if (withdrawalsPaused) revert VaultErrors.WithdrawalsPaused();
        _requireCompliance(msg.sender);
        _accruePerformanceFee();
        uint256 previewAssets = previewRedeem(shares);
        _ensureLiquidity(previewAssets);
        assets = super.redeem(shares, receiver, owner_);
        _adjustHighWaterMarkForPrincipal(-int256(assets));
    }

    /// @notice Non-transferable shares: only mint (from == 0) and burn
    /// (to == 0) are permitted. Structurally removes the "verified
    /// depositor transfers shares to an unverified wallet" bypass
    /// rather than relying on a second, transfer-specific compliance
    /// check (spec §7's chosen MVP architecture).
    function _update(address from, address to, uint256 value) internal override(ERC20) {
        if (from != address(0) && to != address(0)) revert VaultErrors.OnlySelfService();
        super._update(from, to, value);
    }

    function _isCompliant(address user) internal view returns (bool) {
        return COMPLIANCE_VALIDATOR.complianceVerify(address(this), user);
    }

    // ── Emergency withdrawal (always available, even mid-pause) ────────

    /// @notice Burns 100% of the caller's shares and returns their
    /// pro-rata share of the vault's IDLE balance only (never assets
    /// still deployed to the strategy) — deliberately conservative:
    /// pulling from a potentially-impaired strategy is exactly the risk
    /// this path exists to avoid. Available regardless of
    /// `withdrawalsPaused`/`strategyPaused`. Never reverts due to
    /// strategy state, and never promises principal preservation — if
    /// the strategy has suffered a real loss, `assetsReturned` reflects
    /// that honestly rather than papering over it.
    function emergencyWithdraw() external nonReentrant returns (uint256 assetsReturned) {
        _requireCompliance(msg.sender);
        uint256 shares = balanceOf(msg.sender);
        if (shares == 0) revert VaultErrors.ZeroShares();

        uint256 idle = IERC20(asset()).balanceOf(address(this));
        uint256 supply = totalSupply();
        assetsReturned = supply == 0 ? 0 : Math.mulDiv(idle, shares, supply, Math.Rounding.Floor);

        _burn(msg.sender, shares);
        if (assetsReturned > 0) {
            IERC20(asset()).safeTransfer(msg.sender, assetsReturned);
        }
        emit EmergencyWithdrawn(msg.sender, shares, assetsReturned);
    }

    function _ensureLiquidity(uint256 assets) internal {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (idle >= assets) return;
        if (strategyPaused || address(strategy) == address(0)) {
            revert VaultErrors.InsufficientLiquidity(assets, idle);
        }
        strategy.withdraw(assets - idle);
    }

    // ── Strategy management ──────────────────────────────────────────

    /// @notice Replaces the active strategy. Always fully (best-effort)
    /// exits the old strategy via `emergencyWithdraw()` first — never
    /// leaves value orphaned behind a detached pointer. Any shortfall
    /// the old strategy cannot return is a realized loss, honestly
    /// reflected in `totalAssets()` once the pointer is dropped.
    function setStrategy(address newStrategy) external nonReentrant onlyRole(ACCESS_MANAGER.STRATEGY_MANAGER_ROLE()) {
        address old = address(strategy);
        if (old != address(0)) {
            uint256 recovered = IBitVVaultStrategy(old).emergencyWithdraw();
            emit StrategyExited(old, recovered);
        }
        if (newStrategy != address(0)) {
            if (IBitVVaultStrategy(newStrategy).asset() != asset()) revert VaultErrors.StrategyAssetMismatch();
            if (IBitVVaultStrategy(newStrategy).vault() != address(this)) revert VaultErrors.StrategyVaultMismatch();
        }
        strategy = IBitVVaultStrategy(newStrategy);
        emit StrategySet(old, newStrategy);
    }

    /// @notice Pushes idle assets to the active strategy, bounded by
    /// both the allocation cap and the minimum idle reserve — the vault
    /// never deploys so much that it would breach either.
    function allocateToStrategy(uint256 amount) external nonReentrant onlyRole(ACCESS_MANAGER.VAULT_MANAGER_ROLE()) {
        if (strategyPaused) revert VaultErrors.StrategyOperationsPaused();
        if (address(strategy) == address(0)) revert VaultErrors.StrategyNotSet();
        if (amount == 0) revert VaultErrors.ZeroAmount();

        uint256 ta = totalAssets();
        uint256 newStrategyAssets = strategy.totalAssets() + amount;
        uint256 maxAllowed = Math.mulDiv(ta, maxStrategyAllocationBps, BPS_DENOMINATOR);
        if (newStrategyAssets > maxAllowed) {
            revert VaultErrors.StrategyAllocationExceedsCap(newStrategyAssets, maxAllowed);
        }

        uint256 idle = IERC20(asset()).balanceOf(address(this));
        uint256 minIdle = Math.mulDiv(ta, minIdleReserveBps, BPS_DENOMINATOR);
        if (idle < amount || idle - amount < minIdle) {
            revert VaultErrors.InsufficientLiquidity(amount, idle);
        }

        IERC20(asset()).forceApprove(address(strategy), amount);
        strategy.deposit(amount);
        IERC20(asset()).forceApprove(address(strategy), 0);
        emit StrategyAllocated(amount);
    }

    /// @notice Pulls assets back from the active strategy into idle
    /// vault balance, e.g. to top up liquidity ahead of expected
    /// withdrawals.
    function withdrawFromStrategy(uint256 amount) external nonReentrant onlyRole(ACCESS_MANAGER.VAULT_MANAGER_ROLE()) {
        if (strategyPaused) revert VaultErrors.StrategyOperationsPaused();
        if (address(strategy) == address(0)) revert VaultErrors.StrategyNotSet();
        strategy.withdraw(amount);
        emit StrategyWithdrawn(amount);
    }

    /// @notice Best-effort recovery of everything the active strategy
    /// can currently return, even at a loss. Available regardless of
    /// `strategyPaused` — this is the mechanism `strategyPaused` exists
    /// to preserve access to.
    function emergencyExitStrategy() external nonReentrant onlyRole(ACCESS_MANAGER.STRATEGY_MANAGER_ROLE()) {
        if (address(strategy) == address(0)) revert VaultErrors.StrategyNotSet();
        uint256 recovered = strategy.emergencyWithdraw();
        emit StrategyEmergencyExited(address(strategy), recovered);
    }

    // ── Fees ─────────────────────────────────────────────────────────

    /// @dev Mints fee shares to this contract itself (never directly to
    /// TREASURY, which has no mechanism to redeem ERC-4626 shares) only
    /// when `totalAssets()` exceeds the prior all-time peak. Called at
    /// the start of every deposit/mint/withdraw/redeem so the fee is
    /// baked into the share price before the user's own conversion is
    /// computed, and callable standalone via `collectPerformanceFee`.
    function _accruePerformanceFee() internal {
        uint256 currentAssets = totalAssets();
        if (currentAssets <= highWaterMarkAssets) return;

        uint256 profit = currentAssets - highWaterMarkAssets;
        highWaterMarkAssets = currentAssets;

        if (performanceFeeBps == 0 || profit == 0) return;

        uint256 feeAssets = Math.mulDiv(profit, performanceFeeBps, BPS_DENOMINATOR);
        if (feeAssets == 0) return;

        // Shares priced against state *before* this fee's own dilution,
        // matching the standard "mint shares worth the fee at the
        // current price" pattern.
        uint256 feeShares = _convertToShares(feeAssets, Math.Rounding.Floor);
        if (feeShares == 0) return;

        _mint(address(this), feeShares);
        accruedFeeShares += feeShares;
        accruedFeeAssets += feeAssets;
        emit PerformanceFeeAccrued(profit, feeAssets, feeShares);
    }

    /// @dev Keeps `highWaterMarkAssets` tracking genuine strategy-driven
    /// growth only, never principal flow: called after every action that
    /// changes `totalAssets()` by a known, non-yield amount (deposit,
    /// mint, withdraw, redeem, fee collection), bumping the mark by that
    /// same signed delta so the *next* `_accruePerformanceFee()` call
    /// only ever taxes the portion of `totalAssets()` growth that isn't
    /// explained by principal moving in or out. Without this, a second
    /// depositor's contribution would look identical to yield relative
    /// to a mark still sitting at the vault's starting value of 0, and
    /// would be wrongly taxed as profit — a real bug caught during
    /// implementation review, not a hypothetical.
    function _adjustHighWaterMarkForPrincipal(int256 delta) internal {
        if (delta >= 0) {
            highWaterMarkAssets += uint256(delta);
        } else {
            uint256 dec = uint256(-delta);
            highWaterMarkAssets = highWaterMarkAssets > dec ? highWaterMarkAssets - dec : 0;
        }
    }

    /// @notice Redeems the vault's self-held fee shares for underlying
    /// assets and forwards them to BitVTreasury via its existing
    /// `receiveFee` entry point — no second treasury, no new pattern.
    function collectPerformanceFee() external nonReentrant onlyRole(ACCESS_MANAGER.RISK_MANAGER_ROLE())
        returns (uint256 assetsCollected)
    {
        _accruePerformanceFee();
        uint256 feeShares = accruedFeeShares;
        uint256 assets = accruedFeeAssets;
        if (feeShares == 0 || assets == 0) return 0;

        _ensureLiquidity(assets);
        _burn(address(this), feeShares);
        accruedFeeShares = 0;
        accruedFeeAssets = 0;
        _adjustHighWaterMarkForPrincipal(-int256(assets));

        IERC20(asset()).forceApprove(TREASURY, assets);
        BitVTreasury(TREASURY).receiveFee(asset(), assets);

        emit PerformanceFeeCollected(assets, feeShares);
        return assets;
    }

    // ── Admin configuration ──────────────────────────────────────────

    function setPerformanceFeeBps(uint256 newFeeBps) external onlyRole(ACCESS_MANAGER.RISK_MANAGER_ROLE()) {
        if (newFeeBps > MAX_PERFORMANCE_FEE_BPS) revert VaultErrors.InvalidBps(newFeeBps);
        performanceFeeBps = newFeeBps;
        emit PerformanceFeeBpsSet(newFeeBps);
    }

    function setVaultCap(uint256 newCap) external onlyRole(ACCESS_MANAGER.VAULT_MANAGER_ROLE()) {
        vaultCap = newCap;
        emit VaultCapSet(newCap);
    }

    function setMinDeposit(uint256 newMinDeposit) external onlyRole(ACCESS_MANAGER.VAULT_MANAGER_ROLE()) {
        minDeposit = newMinDeposit;
        emit MinDepositSet(newMinDeposit);
    }

    function setMaxStrategyAllocationBps(uint256 bps) external onlyRole(ACCESS_MANAGER.STRATEGY_MANAGER_ROLE()) {
        if (bps > BPS_DENOMINATOR) revert VaultErrors.InvalidBps(bps);
        maxStrategyAllocationBps = bps;
        emit MaxStrategyAllocationBpsSet(bps);
    }

    function setMinIdleReserveBps(uint256 bps) external onlyRole(ACCESS_MANAGER.VAULT_MANAGER_ROLE()) {
        if (bps > BPS_DENOMINATOR) revert VaultErrors.InvalidBps(bps);
        minIdleReserveBps = bps;
        emit MinIdleReserveBpsSet(bps);
    }

    function setDepositsPaused(bool paused) external onlyRole(ACCESS_MANAGER.PAUSER_ROLE()) {
        depositsPaused = paused;
        emit DepositsPausedSet(paused);
    }

    function setWithdrawalsPaused(bool paused) external onlyRole(ACCESS_MANAGER.PAUSER_ROLE()) {
        withdrawalsPaused = paused;
        emit WithdrawalsPausedSet(paused);
    }

    function setStrategyPaused(bool paused) external onlyRole(ACCESS_MANAGER.PAUSER_ROLE()) {
        strategyPaused = paused;
        emit StrategyPausedSet(paused);
    }
}
