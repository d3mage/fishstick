// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "v4-core/libraries/TransientStateLibrary.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {CustomRevert} from "v4-core/libraries/CustomRevert.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

import {TransientStorage} from "./TransientStorage.sol";
import {IFlashConnector} from "./IFlashConnector.sol";

import "forge-std/console.sol";

contract FishstickHook is BaseHook, TransientStorage {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    IFlashConnector private fallbackConnector;

    constructor(
        IPoolManager _manager,
        IFlashConnector _fallbackConnector
    ) BaseHook(_manager) {
        fallbackConnector = _fallbackConnector;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    //todo: to separate file
    struct FlashLoanData {
        address connector;
        uint256 desiredAmount0;
        uint256 desiredAmount1;
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        console.log("Before swap");
        FlashLoanData memory data = abi.decode(hookData, (FlashLoanData));
        console.log(data.connector);

        if (data.connector == address(0)) {
            console.log("Going fallback");
            data.connector = fallbackConnector;
        }

        console.log(data.connector);
        

        // (uint128 amount0, uint128 amount1) = _jitAmounts(key, params);

        // (, , uint128 liquidity) = _createPosition(
        //     key,
        //     params,
        //     amount0,
        //     amount1,
        //     hookData
        // );
        // _storeLiquidity(liquidity);

        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        return (BaseHook.afterSwap.selector, 0);
    }
}
