// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library ComplianceErrors {
    /// @notice Thrown when IAPassComplianceValidator.complianceVerify returns false.
    error ComplianceCheckFailed(address pool, address user);

    /// @notice Thrown if a zero validator address is supplied at construction.
    error ZeroValidatorAddress();

    /// @notice Thrown when calling a function whose economic logic isn't implemented yet.
    error NotImplemented();
}
