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
        if (!((0.01e18 < data.spread) && (data.spread < 0.20e18))) {
            revert("Invalid spread");
        }
        IFlashConnector cn = data.connector == address(0)
            ? fallbackConnector
            : IFlashConnector(data.connector);

        _beforeSwapInline(sender, key, params, data, cn);

        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    function _beforeSwapInline(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        FlashLoanData memory data,
        IFlashConnector cn
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

        console.log(reserve0, reserve1);

        console.log("Balance before");
        console.log(key.currency0.balanceOf(address(this)));
        console.log(key.currency1.balanceOf(address(this)));

        cn.loan(
            Currency.unwrap(key.currency0),
            Currency.unwrap(key.currency1),
            address(this),
            reserve0,
            reserve1
        );

        console.log("Loaned");
        console.log("Balance after loan");
        console.log(key.currency0.balanceOf(address(this)));
        console.log(key.currency1.balanceOf(address(this)));

        //todo: optimize the calls
        (uint160 sqrtPriceX96, int24 tick, , ) = poolManager.getSlot0(
            key.toId()
        );

        (int24 tickLower, int24 tickUpper) = _calculateTicks(
            key,
            sqrtPriceX96,
            tick,
            data.spread,
            params.zeroForOne
        ); //todo: this is  faulty. needs to be fixed
        tickLower = -60; //todo: temp
        tickUpper = 60; //todo: temp

        console.log("TickLower");
        console.logInt(int256(tickLower));
        console.log("TickUpper");
        console.logInt(int256(tickUpper));

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            reserve0,
            reserve1
        );

        console.log("\n");
        console.log("Liquidity before add liq");
        console.log(poolManager.getLiquidity(key.toId()));

        (BalanceDelta totalDelta, BalanceDelta feesAccrued) = poolManager
            .modifyLiquidity(
                key,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: int256(uint256(liquidity)),
                    salt: bytes32(0)
                }),
                "" //we don't provide any hook data
            );

        console.log("Liquidity after add liq");
        console.log(poolManager.getLiquidity(key.toId()));
        console.log("\n");


        console.log("Balance after add liquidity");
        console.log(key.currency0.balanceOf(address(this)));
        console.log(key.currency1.balanceOf(address(this)));
        console.log("\n");

        _storeLiquidity(liquidity);
        _storeTicks(tickLower, tickUpper);
    }

    //todo: create a separate lib with pure functions?
    function _calculateTick(
        uint160 sqrtPriceX96,
        int24 tickSpacing,
        int256 spread //todo: lower the number of conversions
    ) internal pure returns (int24) {
        uint160 sqrtPrice = uint160(
            FixedPointMathLib.mulDivDown(
                uint256(sqrtPriceX96),
                FixedPointMathLib.sqrt(uint256(1e18 + spread)),
                FixedPointMathLib.sqrt(1e18) //todo: hardcode?
            )
        );

        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPrice);
        return (tick / tickSpacing) * tickSpacing;
    }

    function _calculateTicks(
        PoolKey calldata poolKey,
        uint160 sqrtPriceX96, //todo: convert before
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
        
        console.log("Balance after add liquidity");
        console.log(key.currency0.balanceOf(address(this)));
        console.log(key.currency1.balanceOf(address(this)));

        console.log("total delta after swap");
        console.logInt(totalDelta.amount0());
        console.logInt(totalDelta.amount1());
        console.log("fees accrued after swap");
        console.logInt(feesAccrued.amount0());
        console.logInt(feesAccrued.amount1());

        int256 delta0 = poolManager.currencyDelta(address(this), key.currency0);
        int256 delta1 = poolManager.currencyDelta(address(this), key.currency1);
        console.log("After swap delta0");
        console.logInt(delta0);
        console.log("After swap delta1");
        console.logInt(delta1);

        _resolveDeltas(key, delta0, delta1);

        return (BaseHook.afterSwap.selector, 0);
    }

    function _resolveDeltas(
        PoolKey calldata key,
        int256 delta0,
        int256 delta1
    ) internal {
        console.log("d01");
        if (delta0 < 0) {
            // pay currency from an arbitrary capital source to the PoolManager
            _sendToPoolManager(key.currency0, uint256(-delta0));
        } else if (delta0 > 0) {
            // transfer funds to recipient, must use ERC6909 because the swapper has not transferred ERC20 yet
            poolManager.mint(
                tx.origin, //todo: include into calldata
                key.currency0.toId(),
                uint256(delta0)
            );
        }
        console.log("d11");
        if (delta1 < 0) {
            // pay currency from an arbitrary capital source to the PoolManager
            _sendToPoolManager(key.currency1, uint256(-delta1));
        } else if (delta1 > 0) {
            // transfer funds to recipient, must use ERC6909 because the swapper has not transferred ERC20 yet
            poolManager.mint(
                tx.origin, //todo: include into calldata
                key.currency1.toId(),
                uint256(delta1)
            );
        }
    }

    //todo: review this
    function _sendToPoolManager(Currency currency, uint256 amount) internal {
        poolManager.sync(currency);
        console.log(currency.balanceOf(address(this)));
        // IERC20(Currency.unwrap(currency)).transferFrom(
        //     address(this), //todo: TRANSFER FROM USER, NOT HOOK
        //     address(poolManager),
        //     amount
        // );
        currency.transfer(address(poolManager), amount); //todo: THSI IS TO BE REMOVED!!!
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
