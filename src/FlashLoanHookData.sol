// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

    /// @notice Data for the Fishstick hook.
    
    struct FlashLoanHookData {
        uint256 desiredAmount0;
        uint256 desiredAmount1;
        uint256 spread; // 0.01e18 < spread < 0.20e18
        address connector;
        address caller;
    }