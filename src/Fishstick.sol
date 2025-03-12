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
import {IFlashConnector} from "./connectors/IFlashConnector.sol";

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
        uint256 desiredAmount0;
        uint256 desiredAmount1;
        uint256 spread; // 0.01e18 < spread < 0.20e18 
        address connector;
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        console.log("Before swap");
        FlashLoanData memory data = abi.decode(hookData, (FlashLoanData));
        if (!(0.01e18 < data.spread < 0.20e18)) {
            revert("Invalid spread");
        }

        IFlashConnector cn = data.connector == address(0)
            ? fallbackConnector
            : IFlashConnector(data.connector);

        (uint256 reserve0, uint256 reserve1) = cn.getAvailableReserves(
            Currency.unwrap(key.currency0),
            Currency.unwrap(key.currency1)
        );

        uint256 loanAmount0 = reserve0 > data.desiredAmount0
            ? data.desiredAmount0
            : reserve0;
        uint256 loanAmount1 = reserve1 > data.desiredAmount1
            ? data.desiredAmount1
            : reserve1;

        console.log(reserve0, reserve1);

        cn.loan(
            Currency.unwrap(key.currency0),
            Currency.unwrap(key.currency1),
            address(this),
            loanAmount0,
            loanAmount1
        );

        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());

        (int24 tickLower, int24 tickUpper) = _calculateTicks(key, sqrtPriceX96, data.spread, params.zeroForOne);

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            loanAmount0,
            loanAmount1
        );

        _storeLiquidity(liquidity);
        _storeTicks(tickLower, tickUpper);


        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    function _calculateTicks(
        PoolKey calldata poolKey,
        uint160 sqrtPriceX96,   //todo: convert before
        uint256 spread,
        bool zeroForOne
    ) internal pure override returns (int24, int24) {

        uint160 _sqrtPriceLower = uint160(
            FixedPointMathLib.mulDivDown(
                uint256(sqrtPriceX96),
                FixedPointMathLib.sqrt(1e18 - spread),
                FixedPointMathLib.sqrt(1e18) //todo: hardcode?
            )
        );

        uint160 _sqrtPriceUpper = uint160(
            FixedPointMathLib.mulDivDown(
                uint256(sqrtPriceX96),
                FixedPointMathLib.sqrt(1e18 + spread),
                FixedPointMathLib.sqrt(1e18)
            )
        );

        int24 tickLower = TickMath.getTickAtSqrtPrice(
            _sqrtPriceLower
        );
        int24 tickUpper = TickMath.getTickAtSqrtPrice(
            _sqrtPriceUpper
        );

        return (tickLower, tickUpper);
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

    function _modifyLiquidity(
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta,
        bytes calldata hookData
    )
        internal
        virtual
        returns (BalanceDelta totalDelta, BalanceDelta feesAccrued)
    {
        (totalDelta, feesAccrued) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                salt: bytes32(0)
            }),
            hookData
        );
    }
}
