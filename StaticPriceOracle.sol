// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IPriceOracle } from "../interfaces/IPriceOracle.sol";
import { Errors } from "../libraries/Errors.sol";

/// @title StaticPriceOracle
/// @notice Governance/keeper-updatable price oracle with staleness
///         enforcement.
/// @dev This is deliberately NOT a decentralized oracle integration — it is
///      the minimum viable, honestly-labelled implementation of
///      `IPriceOracle` for Monad Testnet deployment, where a Chainlink/Pyth
///      feed for every listed asset may not yet exist. `PRICE_ORACLE` is
///      resolved through `IProtocolRegistry` precisely so this can be
///      swapped for a real aggregator-backed oracle before any mainnet
///      deployment without touching `LendingManager` or `PoolManager` — see
///      `docs/contracts-architecture.md` §Oracle for the production
///      migration path. Shipping this silently as if it were
///      decentralized would misrepresent the protocol's actual trust
///      assumptions; it is called out here and in the deployment script
///      instead.
contract StaticPriceOracle is AccessControl, IPriceOracle {
    bytes32 public constant PRICE_SETTER_ROLE = keccak256("PRICE_SETTER_ROLE");

    /// @notice Prices older than this are treated as unavailable rather than
    ///         used — a stale price silently accepted is more dangerous to a
    ///         lending protocol than an explicit "price unavailable" revert.
    uint256 public constant MAX_STALENESS_SECONDS = 1 hours;

    struct PriceData {
        uint256 priceWad;
        uint256 updatedAt;
    }

    mapping(address asset => PriceData) private _prices;

    event PriceUpdated(address indexed asset, uint256 priceWad, address indexed setter);

    constructor(address admin) {
        if (admin == address(0)) revert Errors.ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PRICE_SETTER_ROLE, admin);
    }

    function setPrice(address asset, uint256 priceWad) external onlyRole(PRICE_SETTER_ROLE) {
        if (priceWad == 0) revert Errors.ZeroAmount();
        _prices[asset] = PriceData({ priceWad: priceWad, updatedAt: block.timestamp });
        emit PriceUpdated(asset, priceWad, msg.sender);
    }

    function getPriceUsd(address asset) external view returns (uint256) {
        PriceData memory data = _prices[asset];
        if (data.updatedAt == 0 || block.timestamp - data.updatedAt > MAX_STALENESS_SECONDS) {
            revert Errors.AssetNotSupported(asset);
        }
        return data.priceWad;
    }

    function isPriceAvailable(address asset) external view returns (bool) {
        PriceData memory data = _prices[asset];
        if (data.updatedAt == 0) return false;
        return block.timestamp - data.updatedAt <= MAX_STALENESS_SECONDS;
    }
}
