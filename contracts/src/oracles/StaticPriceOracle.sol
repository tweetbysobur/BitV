// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {ProtocolErrors} from "../libraries/ProtocolErrors.sol";

/**
 * @title StaticPriceOracle
 * @notice Admin-set price source — NOT a production oracle. Exists only
 * so the lending architecture has something to compile/test against
 * without depending on an unconfirmed external price feed. Deploying
 * this to price real collateral in production would let the owner
 * single-handedly manipulate liquidations; a real deployment needs a
 * decentralized/attested feed behind the same `IPriceOracle` interface
 * instead.
 */
contract StaticPriceOracle is IPriceOracle, Ownable {
    struct PriceData {
        uint256 price;
        uint8 decimals;
        bool isSet;
    }

    mapping(address asset => PriceData) private _prices;

    event PriceSet(address indexed asset, uint256 price, uint8 decimals);

    constructor(address owner_) Ownable(owner_) {}

    function setPrice(address asset, uint256 price, uint8 decimals) external onlyOwner {
        _prices[asset] = PriceData({price: price, decimals: decimals, isSet: true});
        emit PriceSet(asset, price, decimals);
    }

    function getPrice(address asset) external view returns (uint256 price, uint8 decimals) {
        PriceData storage data = _prices[asset];
        if (!data.isSet) revert ProtocolErrors.PriceOracleNotSet(asset);
        return (data.price, data.decimals);
    }
}
