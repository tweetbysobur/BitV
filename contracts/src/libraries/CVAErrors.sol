// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Errors specific to BitVCVAAdapter and CVA-status handling in
/// BitVRWACollateralRegistry — distinct from ProtocolErrors, RWAErrors,
/// ComplianceErrors, and VaultErrors, per the codebase's existing
/// per-domain error library convention.
library CVAErrors {
    error ZeroAddress();

    /// @notice Thrown by `verifyInterface` when no policy contract has
    /// been configured for a token yet.
    error PolicyContractNotSet(address token);

    /// @notice Thrown by `verifyInterface` when the configured policy
    /// contract does not respond to the one confirmed, safely-callable
    /// probe this adapter uses (see BitVCVAAdapter's NatSpec). Does not
    /// imply the token is fraudulent — only that this adapter could not
    /// confirm it behaves like a CVA policy contract.
    error InterfaceVerificationFailed(address token, address policyContract);

    /// @notice Thrown by `previewTransfer` unconditionally — Cleanverse's
    /// `canTransfer` return type, visibility, and rejection mechanism
    /// are not confirmed by the approved specification
    /// (docs/cva-integration-specification.md §5/§6), so this function
    /// exists as an interface boundary without fabricating a call this
    /// codebase cannot make correctly. See
    /// docs/cva-integration-implementation.md.
    error TransferValidationUnconfirmed();
}
