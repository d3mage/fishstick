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
import {FlashLoanHookData} from "./FlashLoanHookData.sol";
import {IFlashConnector} from "./connectors/IFlashConnector.sol";

import "forge-std/console.sol";

contract FishstickHook is BaseHook, TransientStorage {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    // using CurrencyLibrary for Currency;

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

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        console.log("Before swap");
        FlashLoanHookData memory data = abi.decode(
            hookData,
            (FlashLoanHookData)
        );

        if (!((0.01e18 < data.spread) && (data.spread < 0.20e18))) {
            revert("Invalid spread");
        }

        IFlashConnector cn = data.connector == address(0)
            ? fallbackConnector
            : IFlashConnector(data.connector);

        _beforeSwapInline(key, params, data, cn, data.caller);

        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    function _beforeSwapInline(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        FlashLoanHookData memory data,
        IFlashConnector cn,
        address caller
    ) internal {
        (uint256 reserve0, uint256 reserve1) = cn.getAvailableReserves(
            Currency.unwrap(key.currency0),
            Currency.unwrap(key.currency1)
        );

        reserve0 = reserve0 > data.desiredAmount0
            ? data.desiredAmount0
            : reserve0;
        reserve1 = reserve1 > data.desiredAmount1
            ? data.desiredAmount1
            : reserve1;


        cn.loan(
            Currency.unwrap(key.currency0),
            Currency.unwrap(key.currency1),
            caller,
            reserve0,
            reserve1
        );

        (uint160 sqrtPriceX96, int24 tick, , ) = poolManager.getSlot0(
            key.toId()
        );

        (int24 tickLower, int24 tickUpper) = _calculateTicks(
            key,
            uint256(sqrtPriceX96),
            tick,
            data.spread,
            params.zeroForOne
        ); //todo: this is  faulty. needs to be fixed
        tickLower = -120; //todo: temp
        tickUpper = 240; //todo: temp

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            reserve0,
            reserve1
        );

        // (BalanceDelta totalDelta, BalanceDelta feesAccrued) =
        poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: bytes32(0)
            }),
            "" //we don't provide any hook data
        );

        _storeCaller(data.caller);
        _storeLiquidity(liquidity);
        _storeTicks(tickLower, tickUpper);
    }

    //todo: create a separate lib with pure functions?
    function _calculateTick(
        uint256 sqrtPriceX96,
        int24 tickSpacing,
        int256 spread //todo: lower the number of conversions
    ) internal pure returns (int24) {
        uint160 sqrtPrice = uint160(
            FixedPointMathLib.mulDivDown(
                sqrtPriceX96,
                FixedPointMathLib.sqrt(uint256(1e18 + spread)),
                FixedPointMathLib.sqrt(1e18) //todo: hardcode?
            )
        );

        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPrice);
        return (tick / tickSpacing) * tickSpacing;
    }

    function _calculateTicks(
        PoolKey calldata poolKey,
        uint256 sqrtPriceX96,
        int24 poolTick,
        uint256 spread,
        bool zeroForOne
    ) internal pure returns (int24, int24) {
        if (zeroForOne) {
            //if we buy - add liquidity to tick above the current tick
            return (
                poolTick,
                _calculateTick(
                    sqrtPriceX96,
                    poolKey.tickSpacing,
                    int256(spread)
                )
            );
        } else {
            // if we sell - add liquidity to the tick below the current tick
            return (
                _calculateTick(
                    sqrtPriceX96,
                    poolKey.tickSpacing,
                    -int256(spread)
                ),
                poolTick
            );
        }
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        console.log("after swap");
        uint128 liquidity = _loadLiquidity();
        (int24 tickLower, int24 tickUpper) = _loadTicks();

        (BalanceDelta totalDelta, BalanceDelta feesAccrued) = poolManager
            .modifyLiquidity(
                key,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: -int256(uint256(liquidity)),
                    salt: bytes32(0)
                }),
                "" //we don't provide any hook data
            );

        console.log("total delta after swap");
        console.logInt(totalDelta.amount0());
        console.logInt(totalDelta.amount1());
        console.log("fees accrued after swap");
        console.logInt(feesAccrued.amount0());
        console.logInt(feesAccrued.amount1());

        int256 delta0 = poolManager.currencyDelta(address(this), key.currency0);
        int256 delta1 = poolManager.currencyDelta(address(this), key.currency1);
        _resolveDeltas(key, delta0, delta1);

        //todo: repay the loan

        return (BaseHook.afterSwap.selector, 0);
    }

    function _handleDelta(
        Currency currency,
        int256 delta
    ) internal {
        if (delta < 0) {
            _sendToPoolManager(currency, uint256(-delta));
        } else if (delta > 0) {
            poolManager.mint(
                _loadCaller(),
                currency.toId(),
                uint256(delta)
            );
        }
    }

    function _resolveDeltas(
        PoolKey calldata key,
        int256 delta0,
        int256 delta1
    ) internal {
        _handleDelta(key.currency0, delta0);
        _handleDelta(key.currency1, delta1);
    }

    function _sendToPoolManager(Currency currency, uint256 amount) internal {
        poolManager.sync(currency);
        address caller = _loadCaller();

        IERC20(Currency.unwrap(currency)).transferFrom(
            caller,
            address(poolManager),
            amount
        );
        poolManager.settle();
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
