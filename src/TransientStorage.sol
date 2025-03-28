// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract TransientStorage {
    bytes32 constant TICK_LOWER_SLOT = keccak256("tickLower");
    bytes32 constant TICK_UPPER_SLOT = keccak256("tickUpper");
    bytes32 constant LIQUIDITY_SLOT = keccak256("liquidity");
    bytes32 constant CALLER_SLOT = keccak256("caller");
    bytes32 constant RESERVE0_SLOT = keccak256("reserve0");
    bytes32 constant RESERVE1_SLOT = keccak256("reserve1");
    bytes32 constant CN_SLOT = keccak256("cn");

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

    function _storeReserves(uint256 reserve0, uint256 reserve1) internal {
        bytes32 reserve0Slot = RESERVE0_SLOT;
        bytes32 reserve1Slot = RESERVE1_SLOT;

        assembly {
            tstore(reserve0Slot, reserve0)
            tstore(reserve1Slot, reserve1)
        }
    }

    function _loadReserves()
        internal
        view
        returns (uint256 reserve0, uint256 reserve1)
    {
        bytes32 reserve0Slot = RESERVE0_SLOT;
        bytes32 reserve1Slot = RESERVE1_SLOT;
        assembly {
            reserve0 := tload(reserve0Slot)
            reserve1 := tload(reserve1Slot)
        }
    }

    function _storeCN(address cn) internal {
        bytes32 cnSlot = CN_SLOT;
        assembly {
            tstore(cnSlot, cn)
        }
    }

    function _loadCN() internal view returns (address cn) {
        bytes32 cnSlot = CN_SLOT;
        assembly {
            cn := tload(cnSlot)
        }
    }
}
