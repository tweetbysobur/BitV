// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAPassComplianceValidator} from "../interfaces/external/IAPassComplianceValidator.sol";
import {ComplianceErrors} from "../libraries/ComplianceErrors.sol";

/**
 * @title BitVComplianceGuard
 * @notice Shared base for every BitV protocol contract that must gate
 * actions behind Cleanverse's IAPassComplianceValidator. This is
 * BitV's Single-Contract Mode integration: each protected contract holds
 * its own reference to the (single, shared) Cleanverse validator and
 * checks compliance against itself as the `poolAddress`.
 *
 * The validator address is immutable by design: this milestone's testing
 * requirements call for it to not be arbitrarily changeable, and a
 * protocol whose compliance authority could be swapped by a privileged
 * key would undermine the trust guarantee BitV is built on. If Cleanverse
 * documentation later specifies an official upgrade/rotation mechanism
 * for the validator, that supersedes this assumption — see
 * docs/cleanverse-integration.md.
 */
abstract contract BitVComplianceGuard {
    /// @notice The Cleanverse compliance validator this contract trusts.
    IAPassComplianceValidator public immutable COMPLIANCE_VALIDATOR;

    constructor(address complianceValidator) {
        if (complianceValidator == address(0)) revert ComplianceErrors.ZeroValidatorAddress();
        COMPLIANCE_VALIDATOR = IAPassComplianceValidator(complianceValidator);
    }

    /**
     * @notice Reverts unless `user` passes Cleanverse compliance for this
     * contract (used as the `poolAddress` in complianceVerify).
     */
    function _requireCompliance(address user) internal view {
        if (!COMPLIANCE_VALIDATOR.complianceVerify(address(this), user)) {
            revert ComplianceErrors.ComplianceCheckFailed(address(this), user);
        }
    }
}
