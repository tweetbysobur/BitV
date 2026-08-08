// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseModule } from "./BaseModule.sol";
import { IBitScoreManager } from "../interfaces/IBitScoreManager.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title BitScoreManager
/// @notice On-chain reputation store. See `IBitScoreManager` for the
///         BitScore/Cleanverse-tier separation of concerns this contract
///         depends on.
/// @custom:storage-location erc7201:bitv.storage.BitScoreManager
contract BitScoreManager is BaseModule, IBitScoreManager {
    uint256 private constant MAX_SCORE_WAD = 1000e18;
    uint256 private constant BASELINE_SCORE_WAD = 300e18; // starting score for a newly-tracked account

    /// @dev Credit-limit curve constants. `creditLimitUsd` is intentionally a
    ///      simple, auditable piecewise-linear function of score and tier
    ///      rather than a governance-configurable formula — the curve itself
    ///      is a risk parameter the protocol should upgrade (redeploy this
    ///      contract) to change deliberately, not something an admin key can
    ///      silently retune via a setter.
    uint256 private constant BASE_LIMIT_PER_TIER_USD = 50e18; // $50 credit per identity tier point
    uint256 private constant SCORE_MULTIPLIER_DENOMINATOR = MAX_SCORE_WAD;

    struct BitScoreManagerStorage {
        mapping(address account => uint256 scoreWad) scores;
        /// @dev Distinguishes "never scored, read at baseline" from
        ///      "scored, and the score has genuinely decayed to zero" — both
        ///      states have `scores[account] == 0`, and collapsing them
        ///      (treating a stored zero as "uninitialized") would make a
        ///      severely penalized account's score silently bounce back to
        ///      the 300-point baseline on every subsequent read instead of
        ///      staying at the zero it was actually driven to.
        mapping(address account => bool touched) initialized;
        mapping(address reporter => bool authorized) authorizedReporters;
    }

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("bitv.storage.BitScoreManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x8f4af0ca59bb281afb1b8d76c1c23d7b177dffebecb1cdb41f4812175c1d8200;

    function _s() private pure returns (BitScoreManagerStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /// @dev Per-event score deltas, WAD-scaled. Positive events increase
    ///      score toward `MAX_SCORE_WAD`, negative events decrease it toward
    ///      zero — both directions clamp rather than wrap or revert, since a
    ///      score at the boundary receiving another same-direction event is
    ///      an entirely expected occurrence, not an error condition.
    int256 private constant DELTA_ON_TIME_REPAYMENT = 15e18;
    int256 private constant DELTA_LATE_REPAYMENT = -40e18;
    int256 private constant DELTA_LIQUIDATED = -150e18;
    int256 private constant DELTA_SUPPLIED_LIQUIDITY = 5e18;
    int256 private constant DELTA_WITHDREW_LIQUIDITY = -1e18;
    int256 private constant DELTA_IDENTITY_VERIFIED = 100e18;
    int256 private constant DELTA_DECAY = -5e18;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address registry_, address admin) external initializer {
        __BaseModule_init(registry_, admin);
    }

    // ── IBitScoreManager ─────────────────────────────────────────────────

    function scoreOf(address account) public view returns (uint256) {
        // An account with no recorded events yet reads at the baseline
        // rather than zero — zero would understate a brand-new, unproven
        // account's creditworthiness relative to how the credit-limit curve
        // below is calibrated. Gated on `initialized`, NOT on
        // `scores[account] == 0`: a stored zero is a legitimate outcome for
        // an account that has genuinely decayed/been penalized to the floor,
        // and must read as 0, not silently bounce back to baseline.
        if (!_s().initialized[account]) return BASELINE_SCORE_WAD;
        return _s().scores[account];
    }

    function creditLimitUsd(address account, uint16 identityTier)
        external
        view
        returns (uint256 limitWad)
    {
        if (identityTier == 0) return 0; // no unsecured credit without a Cleanverse identity tier

        uint256 score = scoreOf(account);
        uint256 tierLimit = uint256(identityTier) * BASE_LIMIT_PER_TIER_USD;

        // Score scales the tier-derived ceiling linearly from 0% (score = 0)
        // to 100% (score = MAX_SCORE_WAD) — a low-tier, high-score account
        // and a high-tier, low-score account both land below the ceiling a
        // perfect score at that tier would unlock, which is the intended
        // both-signals-matter behaviour.
        return (tierLimit * score) / SCORE_MULTIPLIER_DENOMINATOR;
    }

    /// @dev `magnitudeWad` uses WAD (not a plain multiplier count) so a
    ///      reporter can express "1.5x the normal impact" fractionally, not
    ///      just in whole multiples.
    function reportEvent(address account, ScoreEvent reason, uint256 magnitudeWad) external {
        if (!_s().authorizedReporters[msg.sender]) {
            revert Errors.Unauthorized(msg.sender);
        }

        uint256 previous = scoreOf(account);
        int256 delta = _deltaFor(reason);

        // `magnitudeWad` lets a reporter scale certain events (e.g. a larger
        // liquidation should move the score more than a dust one) without
        // this contract needing an event-specific magnitude parameter for
        // every `ScoreEvent` variant; unused (left at 0 or 1e18) for events
        // whose impact is deliberately flat regardless of size (identity
        // verification, decay).
        int256 scaledDelta = magnitudeWad == 0 ? delta : (delta * int256(magnitudeWad)) / 1e18;

        uint256 newScore = _applyDelta(previous, scaledDelta);
        _s().scores[account] = newScore;
        _s().initialized[account] = true;

        emit ScoreUpdated(account, previous, newScore, reason, msg.sender);
    }

    function setReporterAuthorized(address reporter, bool authorized)
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        _s().authorizedReporters[reporter] = authorized;
        emit ReporterAuthorized(reporter, authorized);
    }

    function isReporterAuthorized(address reporter) external view returns (bool) {
        return _s().authorizedReporters[reporter];
    }

    // ── Internal ─────────────────────────────────────────────────────────

    function _deltaFor(ScoreEvent reason) private pure returns (int256) {
        if (reason == ScoreEvent.OnTimeRepayment) return DELTA_ON_TIME_REPAYMENT;
        if (reason == ScoreEvent.LateRepayment) return DELTA_LATE_REPAYMENT;
        if (reason == ScoreEvent.Liquidated) return DELTA_LIQUIDATED;
        if (reason == ScoreEvent.SuppliedLiquidity) return DELTA_SUPPLIED_LIQUIDITY;
        if (reason == ScoreEvent.WithdrewLiquidity) return DELTA_WITHDREW_LIQUIDITY;
        if (reason == ScoreEvent.IdentityVerified) return DELTA_IDENTITY_VERIFIED;
        return DELTA_DECAY;
    }

    function _applyDelta(uint256 previous, int256 delta) private pure returns (uint256) {
        if (delta >= 0) {
            uint256 next = previous + uint256(delta);
            return next > MAX_SCORE_WAD ? MAX_SCORE_WAD : next;
        }

        uint256 decrease = uint256(-delta);
        return previous > decrease ? previous - decrease : 0;
    }
}
