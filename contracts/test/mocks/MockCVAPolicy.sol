// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IATokenPolicy} from "../../src/interfaces/external/IATokenPolicy.sol";

/// @notice Test-only mock of a Cleanverse CVA policy contract
/// (IATokenPolicy), used solely to exercise BitVCVAAdapter's
/// verifyInterface probe. Responds to getRulesV2 the way a real policy
/// contract is expected to — this does NOT mean this mock is, or
/// stands in for, a genuine Cleanverse-approved CVA policy; it exists
/// only to prove BitVCVAAdapter's on-chain call succeeds against a
/// well-formed responder, exactly mirroring MockComplianceValidator's
/// role for the CVI validator.
contract MockCVAPolicy is IATokenPolicy {
    function getRulesV2(address) external pure returns (RuleV2[] memory rules) {
        rules = new RuleV2[](0);
    }
}

/// @notice Test-only mock that reverts on every call — simulates a
/// malicious or non-conforming contract an admin might (mistakenly or
/// maliciously) configure as a token's policy contract, so
/// verifyInterface's failure path can be tested directly.
contract MockRevertingCVAPolicy {
    fallback() external {
        revert("MockRevertingCVAPolicy: always reverts");
    }
}

/// @notice Test-only mock with no code at all beyond what Solidity
/// generates for an empty contract — calling any function on it
/// reverts because there's no matching selector, exercising the
/// "contract exists but doesn't implement the interface" failure path
/// distinctly from an explicit revert.
contract MockEmptyContract {}
