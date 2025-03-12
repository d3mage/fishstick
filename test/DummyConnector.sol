// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IFlashConnector} from "../src/connectors/IFlashConnector.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

contract DummyConnector is IFlashConnector {
    function loan(
        address token0,
        address token1,
        address where,
        uint256 amount0,
        uint256 amount1
    ) external {
        Currency.wrap(token0).transfer(where, amount0);
        Currency.wrap(token1).transfer(where, amount1);
    }

    function getAvailableReserves(
        address token0,
        address token1
    ) external view returns (uint256, uint256) {
        return (100 ether, 100 ether);
    }
}
