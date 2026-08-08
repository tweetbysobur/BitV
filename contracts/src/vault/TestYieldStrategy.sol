// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBitVVaultStrategy} from "../interfaces/IBitVVaultStrategy.sol";
import {VaultErrors} from "../libraries/VaultErrors.sol";

/**
 * @title TestYieldStrategy
 * @notice ============ NON-PRODUCTION, TEST/DEVELOPMENT ONLY ============
 *
 * This strategy holds deposited funds and does nothing else on its own —
 * it does NOT generate real yield from any real source. Any apparent
 * "yield" only ever comes from `simulateYield`, an unrestricted function
 * that exists purely so BitV's Foundry test suite can exercise
 * share-price growth deterministically without depending on a real
 * external protocol. Never describe this contract, in code, docs, or UI
 * copy, as a production yield source — see
 * docs/yield-vault-specification.md §6 ("TEST STRATEGY" vs. "PRODUCTION
 * STRATEGY") and docs/yield-vault-implementation.md.
 *
 * The constructor requires an explicit `confirmedTestOnlyDeployment`
 * flag so this contract cannot be deployed by accident without the
 * deployer affirmatively acknowledging what it is.
 * =======================================================================
 */
contract TestYieldStrategy is IBitVVaultStrategy {
    using SafeERC20 for IERC20;

    IERC20 public immutable UNDERLYING;
    address public immutable VAULT;

    modifier onlyVault() {
        if (msg.sender != VAULT) revert VaultErrors.CallerNotVault();
        _;
    }

    constructor(address asset_, address vault_, bool confirmedTestOnlyDeployment) {
        if (!confirmedTestOnlyDeployment) revert VaultErrors.NotTestOnlyDeployment();
        if (asset_ == address(0) || vault_ == address(0)) revert VaultErrors.ZeroAddress();
        UNDERLYING = IERC20(asset_);
        VAULT = vault_;
    }

    function asset() external view returns (address) {
        return address(UNDERLYING);
    }

    function vault() external view returns (address) {
        return VAULT;
    }

    function totalAssets() external view returns (uint256) {
        return UNDERLYING.balanceOf(address(this));
    }

    function deposit(uint256 amount) external onlyVault {
        UNDERLYING.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) external onlyVault {
        UNDERLYING.safeTransfer(msg.sender, amount);
    }

    function emergencyWithdraw() external onlyVault returns (uint256 recovered) {
        recovered = UNDERLYING.balanceOf(address(this));
        if (recovered > 0) {
            UNDERLYING.safeTransfer(msg.sender, recovered);
        }
    }

    /// @notice TEST-ONLY: mints no tokens itself — pulls `amount` of the
    /// underlying from the caller (a test harness, already holding a
    /// mock token supply) to simulate this strategy having earned yield.
    /// This is not, and must never be presented as, a real yield source.
    function simulateYield(uint256 amount) external {
        UNDERLYING.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice TEST-ONLY: sends `amount` of held underlying to `to`
    /// without any corresponding vault accounting, simulating a
    /// strategy loss (e.g. an exploited or failed external protocol) so
    /// the vault's honest-loss-reporting behavior can be tested.
    function simulateLoss(uint256 amount, address to) external {
        UNDERLYING.safeTransfer(to, amount);
    }
}
