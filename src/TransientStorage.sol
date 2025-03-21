// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract TransientStorage {
    bytes32 constant TICK_LOWER_SLOT = keccak256("tickLower");
    bytes32 constant TICK_UPPER_SLOT = keccak256("tickUpper");
    bytes32 constant LIQUIDITY_SLOT = keccak256("liquidity");
    bytes32 constant CALLER_SLOT = keccak256("caller");

    function _storeTicks(int24 tickLower, int24 tickUpper) internal {
        bytes32 tickLowerSlot = TICK_LOWER_SLOT;
        bytes32 tickUpperSlot = TICK_UPPER_SLOT;
        assembly {
            tstore(tickLowerSlot, tickLower)
            tstore(tickUpperSlot, tickUpper)
        }
    }

    function _loadTicks()
        internal
        view
        returns (int24 tickLower, int24 tickUpper)
    {
        bytes32 tickLowerSlot = TICK_LOWER_SLOT;
        bytes32 tickUpperSlot = TICK_UPPER_SLOT;
        assembly {
            tickLower := tload(tickLowerSlot)
            tickUpper := tload(tickUpperSlot)
        }
    }

    function _storeLiquidity(uint128 liquidity) internal {
        bytes32 liquiditySlot = LIQUIDITY_SLOT;
        assembly {
            tstore(liquiditySlot, liquidity)
        }
    }

    /// @dev Read the liquidity of the position created in beforeSwap
    function _loadLiquidity() internal view returns (uint128 liquidity) {
        bytes32 liquiditySlot = LIQUIDITY_SLOT;
        assembly {
            liquidity := tload(liquiditySlot)
        }
    }

    function _storeCaller(address _caller) internal {
        bytes32 callerSlot = CALLER_SLOT;
        assembly {
            tstore(callerSlot, _caller)
        }
    }

    function _loadCaller() internal view returns (address _caller) {
        bytes32 callerSlot = CALLER_SLOT;
        assembly {
            _caller := tload(callerSlot)
        }
    }
}
