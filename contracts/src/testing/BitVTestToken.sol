// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BitVTestToken
 * @notice ============ NON-PRODUCTION, TESTNET-ONLY ASSET ============
 *
 * A plain, owner-mintable ERC-20 with no real backing, no issuer, and no
 * Cleanverse recognition of any kind. Exists solely so BitV's Monad
 * Testnet deployment has a concrete asset to configure pools, RWA
 * registration, and yield vaults against, without depending on finding
 * or guessing a real third-party token's testnet address (see
 * docs/testnet-assets.md — no real, confirmed Monad Testnet asset
 * address was available at deployment time).
 *
 * This token is never a Cleanverse Verified Asset (CVA). Nothing in
 * this contract, its deployment, or its configuration constitutes or
 * implies Cleanverse approval — see docs/cva.md-family documents for
 * what an actual CVA claim requires (Cleanverse's own confirmation,
 * never a BitV-internal one).
 *
 * The constructor requires an explicit `confirmedTestOnlyDeployment`
 * flag, mirroring `contracts/src/vault/TestYieldStrategy.sol`'s
 * existing pattern, so this contract cannot be deployed by accident
 * without the deployer affirmatively acknowledging what it is.
 */
contract BitVTestToken is ERC20, Ownable {
    error NotTestOnlyDeployment();

    uint8 private immutable _decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address owner_,
        bool confirmedTestOnlyDeployment
    ) ERC20(name_, symbol_) Ownable(owner_) {
        if (!confirmedTestOnlyDeployment) revert NotTestOnlyDeployment();
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice TEST-ONLY: owner-gated mint, so the deployer can fund
    /// test wallets for the smoke test in docs/testnet-smoke-test.md.
    /// No real value backs this token regardless of supply minted.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
