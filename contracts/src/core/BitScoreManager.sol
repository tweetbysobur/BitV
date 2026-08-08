// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ComplianceErrors} from "../libraries/ComplianceErrors.sol";

/**
 * @title BitScoreManager
 * @notice BitV-native risk scoring system. BitScore is NOT a Cleanverse
 * primitive — it is BitV's own risk layer, which will read verified
 * identity information (once available) plus protocol activity to
 * determine borrowing limits, LTV, interest tier, pool eligibility, and
 * yield access. Compliance foundation milestone: no scoring logic yet.
 */
contract BitScoreManager {
    function getBitScore(address user) external pure returns (uint256) {
        (user);
        revert ComplianceErrors.NotImplemented();
    }
}
