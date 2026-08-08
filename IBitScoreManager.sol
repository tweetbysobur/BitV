// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IBitScoreManager
/// @notice On-chain reputation store. BitScore is the signal LendingManager
///         reads to size an identity-based under-collateralized credit line
///         (see docs/contracts-architecture.md §BitScore) — everything here
///         exists to answer LendingManager's one question: "how much
///         unsecured credit does this account currently qualify for".
/// @dev Deliberately NOT an oracle-fed number. BitScore here is a protocol-
///      native reputation score, updated by BitV's own contracts reacting to
///      BitV's own events (on-time repayment, liquidation, deposit history)
///      — it is a separate signal from Cleanverse's identity tier, which
///      answers "who is this" rather than "how has this account behaved on
///      BitV". The two compose: `IAccessManager`/`IIdentityOracle` gate
///      WHETHER an account may use a market at all; BitScore then determines
///      the TERMS once inside it.
interface IBitScoreManager {
    /// @notice Reasons a score can move, so `ScoreUpdated` carries enough
    ///         information for the frontend's BitScore history view to
    ///         render a meaningful factor breakdown rather than a bare delta.
    enum ScoreEvent {
        OnTimeRepayment,
        LateRepayment,
        Liquidated,
        SuppliedLiquidity,
        WithdrewLiquidity,
        IdentityVerified, // Cleanverse tier increase, forwarded by AccessManager
        Decay // periodic decay toward baseline for inactive accounts
    }

    event ScoreUpdated(
        address indexed account,
        uint256 previousScore,
        uint256 newScore,
        ScoreEvent indexed reason,
        address indexed reporter
    );
    event ReporterAuthorized(address indexed reporter, bool authorized);

    /// @notice Current BitScore, WAD-scaled, 0-1000 range (0e18-1000e18).
    ///         Range chosen to match the frontend's existing display
    ///         convention rather than introducing a second scale the UI
    ///         would need to translate.
    function scoreOf(address account) external view returns (uint256 scoreWad);

    /// @notice Derived credit limit in USD (WAD) for identity-based
    ///         under-collateralized borrowing, as a pure function of score
    ///         and identity tier. LendingManager calls this directly rather
    ///         than reimplementing the score→limit curve itself, so the
    ///         curve can be retuned by upgrading this contract alone.
    function creditLimitUsd(address account, uint16 identityTier)
        external
        view
        returns (uint256 limitWad);

    /// @notice Only callable by contracts holding `REPORTER_ROLE`
    ///         (LendingManager, VaultManager, AccessManager) — a score update
    ///         must always be attributable to a specific, authorized protocol
    ///         event, never to an arbitrary caller.
    function reportEvent(address account, ScoreEvent reason, uint256 magnitudeWad) external;

    function setReporterAuthorized(address reporter, bool authorized) external;
}
