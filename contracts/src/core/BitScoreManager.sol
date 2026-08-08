// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BitVRoleConsumer} from "../access/BitVRoleConsumer.sol";
import {ProtocolErrors} from "../libraries/ProtocolErrors.sol";
import {IBitScoreManager} from "../interfaces/IBitScoreManager.sol";

/**
 * @title BitScoreManager
 * @notice BitV's protocol-level risk layer, per
 * docs/bitscore-specification.md. NOT a Cleanverse primitive — CVI
 * (`IAPassComplianceValidator.complianceVerify`) remains the sole
 * eligibility gate; BitScore only ever adjusts *how favorable* terms
 * are for an already-eligible user, within the asset's own configured
 * ceilings. This contract has no knowledge of, and never calls,
 * `IAPassComplianceValidator` — the two systems stay structurally
 * separate, not just separate by convention.
 *
 * Implementation note (deviation from the spec's illustrative decay
 * design, documented here and in docs/bitscore-implementation.md): the
 * spec sketched separate decay windows per input category (repayments
 * 180d, utilization/collateralization 30d). This implementation
 * consolidates all positive inputs into a single decaying
 * `positiveContribution` accumulator with one decay window, for a
 * simpler, more auditable state model — the per-input *point values*
 * and the overall *cap* are preserved from the spec; only the "how many
 * separate decay clocks" mechanic was simplified. Liquidation penalties
 * decay on their own, slower clock; bad-debt penalties never decay —
 * both exactly as specified.
 */
contract BitScoreManager is BitVRoleConsumer, IBitScoreManager {
    struct ScoreState {
        bool initialized;
        uint16 positiveContribution; // capped, decaying accumulator (repayments/timeliness/tenure/utilization)
        uint40 lastPositiveUpdateTimestamp;
        uint16 liquidationPenalty; // decaying
        uint40 lastLiquidationTimestamp;
        uint16 badDebtPenalty; // permanent, never decays
        uint16 tenureCredited; // portion of positiveContribution already attributed to tenure, so tenure isn't re-added every call
        uint32 successfulRepayments;
        uint32 liquidationCount;
        uint32 badDebtCount;
        uint40 firstActivityTimestamp;
    }

    struct Params {
        uint16 startScore; // 300
        uint16 maxPositiveContribution; // 700 -> max score 1000
        uint32 positiveDecayWindowSeconds; // 180 days
        uint32 liquidationDecayWindowSeconds; // 365 days
        uint16 repaymentPoints; // +5 per qualifying full-close repayment
        uint16 timelinessPoints; // +2 per qualifying repayment closed while healthy
        uint32 minPositionDurationSeconds; // 1 day — below this, zero credit (anti-gaming)
        uint32 tenurePeriodSeconds; // 30 days
        uint16 tenurePointsPerPeriod; // +1 per period
        uint16 tenureCap; // 50 total from tenure
        uint16 fullLiquidationPenalty; // -100
        uint16 partialLiquidationPenalty; // -50
        uint16 badDebtPenaltyPoints; // -300, never decays
        uint16 lowUtilizationBonusPoints; // +1, sustained low utilization/high health factor
        uint16 lowUtilizationThresholdBps; // e.g. 3000 = 30%
        uint16 healthyHealthFactorBps; // e.g. 15000 = 1.5x, in "healthFactorBps" terms as passed by the caller
    }

    uint16 public constant MIN_SCORE = 0;
    uint16 public constant MAX_SCORE = 1000;
    uint16 public constant TIER_1_FLOOR = 250; // Standard
    uint16 public constant TIER_2_FLOOR = 500; // Established
    uint16 public constant TIER_3_FLOOR = 750; // Trusted

    // Build 04: bounded, deterministic per-tier LTV headroom fractions
    // (of the gap between base ltvBps and the asset's configured
    // maxLtvWithScoreBps) and interest quote discounts. Tier 0 instead
    // applies a *protective reduction* fraction to the base available
    // borrow value. All RISK_MANAGER_ROLE-tunable via setTierAdjustments.
    struct TierAdjustment {
        int16 ltvHeadroomBps; // Tier1-3: 0..10000 fraction of headroom granted; Tier0: negative = protective reduction fraction of base
        uint256 baseRateDiscountRay; // quoted only, see IBitScoreManager.getBaseRateDiscountRay
    }

    Params public params;
    TierAdjustment[4] public tierAdjustments; // indexed by tier 0-3

    mapping(address user => ScoreState) private _scores;

    address public lendingManager;

    event LendingManagerSet(address indexed lendingManager);
    event ParamsUpdated();
    event TierAdjustmentsUpdated();
    event ScoreUpdated(address indexed user, uint16 oldScore, uint16 newScore, bytes32 reason);
    event TierChanged(address indexed user, uint8 oldTier, uint8 newTier);
    event EmergencyReset(address indexed user, address indexed admin);

    modifier onlyLendingManager() {
        if (msg.sender != lendingManager) revert ProtocolErrors.CallerNotLendingManager();
        _;
    }

    constructor(address accessManager) BitVRoleConsumer(accessManager) {
        params = Params({
            startScore: 300,
            maxPositiveContribution: 700,
            positiveDecayWindowSeconds: 180 days,
            liquidationDecayWindowSeconds: 365 days,
            repaymentPoints: 5,
            timelinessPoints: 2,
            minPositionDurationSeconds: 1 days,
            tenurePeriodSeconds: 30 days,
            tenurePointsPerPeriod: 1,
            tenureCap: 50,
            fullLiquidationPenalty: 100,
            partialLiquidationPenalty: 50,
            badDebtPenaltyPoints: 300,
            lowUtilizationBonusPoints: 1,
            lowUtilizationThresholdBps: 3_000,
            healthyHealthFactorBps: 15_000
        });

        // Tier 0 (Restricted): protective 20% reduction of base available borrow value.
        tierAdjustments[0] = TierAdjustment({ltvHeadroomBps: -2_000, baseRateDiscountRay: 0});
        // Tier 1 (Standard): no adjustment — base parameters exactly.
        tierAdjustments[1] = TierAdjustment({ltvHeadroomBps: 0, baseRateDiscountRay: 0});
        // Tier 2 (Established): half the available LTV headroom, small rate discount (0.5%).
        tierAdjustments[2] = TierAdjustment({ltvHeadroomBps: 5_000, baseRateDiscountRay: 5e24});
        // Tier 3 (Trusted): full available LTV headroom, larger rate discount (1%).
        tierAdjustments[3] = TierAdjustment({ltvHeadroomBps: 10_000, baseRateDiscountRay: 1e25});
    }

    // ── Admin ────────────────────────────────────────────────────────────

    function setLendingManager(address lendingManager_) external onlyRole(ACCESS_MANAGER.PROTOCOL_ADMIN_ROLE()) {
        if (lendingManager_ == address(0)) revert ProtocolErrors.ZeroAddress();
        lendingManager = lendingManager_;
        emit LendingManagerSet(lendingManager_);
    }

    function setParams(Params calldata newParams) external onlyRole(ACCESS_MANAGER.RISK_MANAGER_ROLE()) {
        if (newParams.maxPositiveContribution > MAX_SCORE) revert ProtocolErrors.InvalidRiskParams();
        params = newParams;
        emit ParamsUpdated();
    }

    function setTierAdjustments(TierAdjustment[4] calldata newAdjustments)
        external
        onlyRole(ACCESS_MANAGER.RISK_MANAGER_ROLE())
    {
        for (uint256 i = 0; i < 4; i++) {
            if (newAdjustments[i].ltvHeadroomBps > 10_000 || newAdjustments[i].ltvHeadroomBps < -10_000) {
                revert ProtocolErrors.InvalidRiskParams();
            }
            tierAdjustments[i] = newAdjustments[i];
        }
        emit TierAdjustmentsUpdated();
    }

    /// @notice Governance-only emergency reset — the sole score reset
    /// path (docs/bitscore-specification.md §3: no user-triggered or
    /// automatic reset exists). Emits a distinct event so this is
    /// auditable as an exceptional action, not confused with normal
    /// score movement.
    function emergencyResetScore(address user) external onlyRole(ACCESS_MANAGER.RISK_MANAGER_ROLE()) {
        delete _scores[user];
        emit EmergencyReset(user, msg.sender);
    }

    // ── Views ────────────────────────────────────────────────────────────

    function getScore(address user) public view returns (uint16) {
        ScoreState storage s = _scores[user];
        if (!s.initialized) return params.startScore;

        uint256 decayedPositive = _decay(s.positiveContribution, s.lastPositiveUpdateTimestamp, params.positiveDecayWindowSeconds);
        uint256 decayedLiquidation =
            _decay(s.liquidationPenalty, s.lastLiquidationTimestamp, params.liquidationDecayWindowSeconds);

        int256 raw = int256(uint256(params.startScore)) + int256(decayedPositive) - int256(decayedLiquidation)
            - int256(uint256(s.badDebtPenalty));

        if (raw < int256(uint256(MIN_SCORE))) return MIN_SCORE;
        if (raw > int256(uint256(MAX_SCORE))) return MAX_SCORE;
        return uint16(uint256(raw));
    }

    function getTier(address user) public view returns (uint8) {
        return _tierOf(getScore(user));
    }

    /// @notice Raw (pre-decay-application-at-read-time is already
    /// reflected in `getScore`; this exposes the underlying accumulator
    /// state itself) — useful for frontends/indexers that want to show
    /// e.g. repayment counts directly, without recomputing decay.
    function getRawState(address user)
        external
        view
        returns (
            uint16 positiveContribution,
            uint16 liquidationPenalty,
            uint16 badDebtPenalty,
            uint32 successfulRepayments,
            uint32 liquidationCount,
            uint32 badDebtCount
        )
    {
        ScoreState storage s = _scores[user];
        return (
            s.positiveContribution,
            s.liquidationPenalty,
            s.badDebtPenalty,
            s.successfulRepayments,
            s.liquidationCount,
            s.badDebtCount
        );
    }

    /// @notice The struct-typed equivalent of the auto-generated `params()`
    /// getter (which unpacks into a tuple) — convenient for callers that
    /// want to read-modify-write via `setParams`.
    function getParams() external view returns (Params memory) {
        return params;
    }

    function _tierOf(uint16 score) internal pure returns (uint8) {
        if (score >= TIER_3_FLOOR) return 3;
        if (score >= TIER_2_FLOOR) return 2;
        if (score >= TIER_1_FLOOR) return 1;
        return 0;
    }

    /// @notice Bounded, deterministic LTV-headroom adjustment. Always
    /// within [0, maxAvailableBorrowValue] by construction — see
    /// docs/bitscore-implementation.md's "Why this is provably bounded"
    /// section. `maxAvailableBorrowValue` already reflects
    /// BitVPoolManager's own `maxLtvWithScoreBps` ceiling, so this
    /// function has no way to exceed the asset's own configured limit.
    function getAdjustedAvailableBorrowValue(
        address user,
        uint256 baseAvailableBorrowValue,
        uint256 maxAvailableBorrowValue,
        uint256 totalDebtValue,
        uint256 totalCollateralValue
    ) external view returns (uint256) {
        // If maxAvailableBorrowValue <= baseAvailableBorrowValue, there's
        // no headroom configured for this asset combination (e.g.
        // maxLtvWithScoreBps == ltvBps) — the bonus branch below falls
        // through to returning baseAvailableBorrowValue unchanged. Tier
        // 0's protective reduction still applies regardless.
        TierAdjustment memory adj = tierAdjustments[getTier(user)];

        if (adj.ltvHeadroomBps < 0) {
            uint256 reduction = baseAvailableBorrowValue * uint256(uint16(-adj.ltvHeadroomBps)) / 10_000;
            return baseAvailableBorrowValue > reduction ? baseAvailableBorrowValue - reduction : 0;
        }

        if (adj.ltvHeadroomBps == 0 || maxAvailableBorrowValue <= baseAvailableBorrowValue) {
            return baseAvailableBorrowValue;
        }

        uint256 headroom = maxAvailableBorrowValue - baseAvailableBorrowValue;

        // Temper the bonus by current utilization: full bonus at 0%
        // utilization, zero bonus at 100% — see
        // docs/bitscore-specification.md §7's "current utilization
        // tempers rather than blocks" rule.
        uint256 utilizationBps = totalCollateralValue == 0 ? 0 : (totalDebtValue * 10_000) / totalCollateralValue;
        if (utilizationBps > 10_000) utilizationBps = 10_000;
        uint256 temperBps = 10_000 - utilizationBps;

        uint256 bonus = headroom * uint256(uint16(adj.ltvHeadroomBps)) / 10_000 * temperBps / 10_000;
        uint256 adjusted = baseAvailableBorrowValue + bonus;

        // Hard ceiling — provably cannot exceed the asset's own configured maximum.
        return adjusted > maxAvailableBorrowValue ? maxAvailableBorrowValue : adjusted;
    }

    function getBaseRateDiscountRay(address user) external view returns (uint256) {
        return tierAdjustments[getTier(user)].baseRateDiscountRay;
    }

    // ── Record functions (BitVLendingManager only) ──────────────────────

    function recordRepayment(address user, bool wasFullClose, uint256 positionDurationSeconds)
        external
        onlyLendingManager
    {
        ScoreState storage s = _scores[user];
        uint16 scoreBefore = getScore(user);
        uint8 tierBefore = _tierOf(scoreBefore);
        _ensureInitialized(s);

        if (positionDurationSeconds >= params.minPositionDurationSeconds) {
            int256 delta = int256(uint256(params.repaymentPoints));
            if (wasFullClose) {
                delta += int256(uint256(params.timelinessPoints));
                s.successfulRepayments += 1;
            }
            _applyPositiveDelta(s, delta);
            _applyTenureCredit(s);
        }
        // Below minimum duration: zero credit, per spec's explicit
        // anti-gaming rule — but activity timestamps still update via
        // _ensureInitialized so the wallet's existence is recorded
        // without granting any score benefit for the fast cycle itself.

        _emitScoreChange(user, scoreBefore, tierBefore, "repayment");
    }

    function recordLiquidation(address user, bool wasBadDebt, bool wasPartial) external onlyLendingManager {
        ScoreState storage s = _scores[user];
        uint16 scoreBefore = getScore(user);
        uint8 tierBefore = _tierOf(scoreBefore);
        _ensureInitialized(s);

        if (wasBadDebt) {
            uint256 newBadDebt = uint256(s.badDebtPenalty) + uint256(params.badDebtPenaltyPoints);
            s.badDebtPenalty = newBadDebt > type(uint16).max ? type(uint16).max : uint16(newBadDebt);
            s.badDebtCount += 1;
        } else {
            uint16 points = wasPartial ? params.partialLiquidationPenalty : params.fullLiquidationPenalty;
            _applyLiquidationPenalty(s, points);
            s.liquidationCount += 1;
        }

        _emitScoreChange(user, scoreBefore, tierBefore, wasBadDebt ? bytes32("bad_debt") : bytes32("liquidation"));
    }

    function recordUtilizationSnapshot(address user, uint16 utilizationBps, uint16 healthFactorBps)
        external
        onlyLendingManager
    {
        ScoreState storage s = _scores[user];
        uint16 scoreBefore = getScore(user);
        uint8 tierBefore = _tierOf(scoreBefore);
        _ensureInitialized(s);

        if (utilizationBps <= params.lowUtilizationThresholdBps && healthFactorBps >= params.healthyHealthFactorBps) {
            _applyPositiveDelta(s, int256(uint256(params.lowUtilizationBonusPoints)));
        }
        // Deliberately no negative adjustment for high utilization via
        // this path — see docs/bitscore-implementation.md's documented
        // simplification. Sustained risky behavior is still captured
        // indirectly: it's what leads to liquidations, which are penalized.

        _emitScoreChange(user, scoreBefore, tierBefore, "utilization_snapshot");
    }

    // ── Internal ─────────────────────────────────────────────────────────

    function _ensureInitialized(ScoreState storage s) internal {
        if (!s.initialized) {
            s.initialized = true;
            s.firstActivityTimestamp = uint40(block.timestamp);
        }
    }

    function _applyTenureCredit(ScoreState storage s) internal {
        if (s.firstActivityTimestamp == 0) return;
        uint256 elapsed = block.timestamp - s.firstActivityTimestamp;
        uint256 periodsElapsed = elapsed / params.tenurePeriodSeconds;
        uint256 earned = periodsElapsed * params.tenurePointsPerPeriod;
        if (earned > params.tenureCap) earned = params.tenureCap;
        if (earned > s.tenureCredited) {
            uint256 delta = earned - s.tenureCredited;
            s.tenureCredited = uint16(earned);
            _applyPositiveDelta(s, int256(delta));
        }
    }

    function _applyPositiveDelta(ScoreState storage s, int256 delta) internal {
        uint256 decayed = _decay(s.positiveContribution, s.lastPositiveUpdateTimestamp, params.positiveDecayWindowSeconds);
        int256 newValue = int256(decayed) + delta;
        if (newValue < 0) newValue = 0;
        if (newValue > int256(uint256(params.maxPositiveContribution))) {
            newValue = int256(uint256(params.maxPositiveContribution));
        }
        s.positiveContribution = uint16(uint256(newValue));
        s.lastPositiveUpdateTimestamp = uint40(block.timestamp);
    }

    function _applyLiquidationPenalty(ScoreState storage s, uint16 points) internal {
        uint256 decayed = _decay(s.liquidationPenalty, s.lastLiquidationTimestamp, params.liquidationDecayWindowSeconds);
        uint256 newValue = decayed + uint256(points);
        s.liquidationPenalty = newValue > type(uint16).max ? type(uint16).max : uint16(newValue);
        s.lastLiquidationTimestamp = uint40(block.timestamp);
    }

    function _decay(uint16 raw, uint40 lastUpdate, uint32 window) internal view returns (uint256) {
        if (raw == 0) return 0;
        if (lastUpdate == 0) return raw;
        uint256 elapsed = block.timestamp - uint256(lastUpdate);
        if (elapsed >= window) return 0;
        return (uint256(raw) * (uint256(window) - elapsed)) / window;
    }

    function _emitScoreChange(address user, uint16 scoreBefore, uint8 tierBefore, bytes32 reason) internal {
        uint16 scoreAfter = getScore(user);
        emit ScoreUpdated(user, scoreBefore, scoreAfter, reason);
        uint8 tierAfter = _tierOf(scoreAfter);
        if (tierAfter != tierBefore) {
            emit TierChanged(user, tierBefore, tierAfter);
        }
    }
}
