// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BitVComplianceGuard} from "../../src/compliance/BitVComplianceGuard.sol";
import {ComplianceErrors} from "../../src/libraries/ComplianceErrors.sol";

/// @notice Minimal test-only harness for BitVComplianceGuard, decoupled
/// from any real protocol contract's economics — used so compliance-gate
/// unit tests don't depend on BitVPoolManager's constructor/state.
contract ComplianceGuardHarness is BitVComplianceGuard {
    constructor(address complianceValidator, address owner_) BitVComplianceGuard(complianceValidator, owner_) {}

    function protectedAction() external {
        _requireCompliance(msg.sender);
        revert ComplianceErrors.NotImplemented();
    }
}
