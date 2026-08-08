// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IBitVCVAAdapter
 * @notice Boundary between BitVRWACollateralRegistry (and, in future
 * milestones, BitVLendingManager/BitVYieldVault) and Cleanverse's CVA
 * (Cleanverse Verified Asset) policy interface. Per
 * docs/cva-integration-specification.md §6/§14 (architecture decision
 * D): this adapter is the **only** BitV component that calls
 * Cleanverse CVA-specific interfaces — every other contract asks the
 * adapter, never Cleanverse's `IATokenPolicy` directly.
 *
 * Kept narrow and replaceable: a future Cleanverse interface change
 * only requires a new adapter implementation behind this same
 * interface, mirroring how `IBitScoreManager`/`IRWACollateralRegistry`
 * already insulate their consumers from implementation details.
 *
 * Every function here answers a question about on-chain, verifiable
 * behavior only. None of them, individually or combined, prove
 * Cleanverse's own off-chain approval of a token as a CVA — see
 * `isRecognizedCVA`'s NatSpec and
 * docs/cva-integration-specification.md §2/§7/§13 for why that
 * verification gap is structural, not a bug to be fixed by a better
 * adapter.
 */
interface IBitVCVAAdapter {
    /// @notice True only if `token` has a configured policy contract
    /// AND that contract has been successfully probed (see
    /// `BitVCVAAdapter.verifyInterface`) to respond the way a CVA
    /// policy contract is expected to. This proves the token *behaves
    /// like* a CVA on-chain — it does NOT prove Cleanverse approved
    /// `token` as a CVA off-chain, since no on-chain query for that
    /// fact is confirmed to exist. Callers must never treat `true` here
    /// as equivalent to official Cleanverse verification.
    function isRecognizedCVA(address token) external view returns (bool);

    /// @notice The policy contract address configured for `token`, or
    /// `address(0)` if none has been set.
    function policyOf(address token) external view returns (address);

    /// @notice Intended to preview whether a specific transfer would be
    /// permitted by `token`'s CVA policy. Cleanverse's `canTransfer`
    /// return type, visibility, and rejection mechanism (revert vs.
    /// boolean) are not confirmed by the approved specification
    /// (docs/cva-integration-specification.md §5/§6) — this function
    /// exists as the interface boundary Build 07.1 requires, but its
    /// implementation deliberately does not fabricate a call it cannot
    /// make correctly; see the implementing contract's NatSpec.
    function previewTransfer(address token, address from, address to, uint256 amount)
        external
        view
        returns (bool permitted);

    /// @notice Whether `token` is currently usable for CVA-specific
    /// purposes — today, identical to `isRecognizedCVA`; kept as a
    /// separate function so a future adapter-level suspension concept
    /// (independent of interface recognition) can be added without an
    /// interface break.
    function isCurrentlyUsable(address token) external view returns (bool);
}
