// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title BitVReceiptToken
/// @notice Scaled-balance receipt token for a single `PoolManager` pool —
///         the "aToken" referenced throughout `IPoolManager`. One instance is
///         deployed per pool by `PoolManager.createPool`.
/// @dev Deliberately NOT the source of truth for a holder's balance: it
///      exists as a transferable, composable ERC20 representation of a
///      supply position, but `PoolManager` computes the actual
///      liquidity-index-scaled balance and calls `mint`/`burn` here to keep
///      this token's ledger in sync. This mirrors Aave's aToken design for a
///      specific reason relevant to Monad — keeping balance SCALING logic
///      (dividing by the liquidity index) inside `PoolManager` rather than
///      inside this token means every pool's index arithmetic lives in one
///      audited contract instead of being re-implemented, and potentially
///      re-broken, per deployed receipt token.
///
///      `mint`/`burn` are restricted to `owner` (set to `PoolManager` at
///      construction, immutable thereafter — there is deliberately no
///      `transferOwnership`, since a receipt token whose mint authority
///      could be reassigned post-deployment is a direct path to unbacked
///      supply).
contract BitVReceiptToken is ERC20 {
    address public immutable owner;
    address public immutable underlyingAsset;

    constructor(address owner_, address underlyingAsset_, string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
    {
        if (owner_ == address(0) || underlyingAsset_ == address(0)) revert Errors.ZeroAddress();
        owner = owner_;
        underlyingAsset = underlyingAsset_;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Errors.Unauthorized(msg.sender);
        _;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    /// @dev Matches the underlying asset's decimals rather than a fixed 18
    ///      — a receipt token for a 6-decimal asset (e.g. USDC) that reports
    ///      18 decimals would display balances 10^12x too large in any
    ///      wallet or explorer that reads `decimals()` directly.
    function decimals() public view override returns (uint8) {
        return ERC20(underlyingAsset).decimals();
    }
}
