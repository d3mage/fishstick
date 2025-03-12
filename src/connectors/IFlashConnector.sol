// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev A generic interface for connecting to different protocols
interface IFlashConnector {
    function loan(
        address token0,
        address token1,
        address where,
        uint256 amount0,
        uint256 amount1
    ) external;

    function getAvailableReserves(
        address token0,
        address token1
    ) external view returns (uint256, uint256);
}
