// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev A generic interface for connecting to different protocols
interface IFlashConnector {
    function flashLoan(bytes memory data) external;
}
