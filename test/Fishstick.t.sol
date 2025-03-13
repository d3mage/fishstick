// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import "forge-std/console.sol"; //todo: remove
import {FishstickHook} from "../src/Fishstick.sol";
import {IFlashConnector} from "../src/connectors/IFlashConnector.sol";
import {FlashLoanHookData} from "../src/FlashLoanHookData.sol";
import {DummyConnector} from "./DummyConnector.sol";

contract TestFishtick is Test, Deployers {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    MockERC20 token0; // USDC
    MockERC20 token1; // wBTC
    MockERC20 token2; // wSOL

    PoolKey pk0;
    PoolKey pk1;

    FishstickHook hook;

    address alice = makeAddr("ALICE");

    function tokenConfiguration(
        MockERC20 _token0,
        MockERC20 _token1,
        int24 _l_Tick,
        int24 _u_Tick,
        IHooks _hook
    ) internal returns (PoolKey memory pk) {
        (pk, ) = initPool(
            Currency.wrap(address(_token0)),
            Currency.wrap(address(_token1)),
            IHooks(_hook), // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1 // Initial Sqrt(P) value = 1
        );

        _token0.mint(address(this), 10000 ether);
        _token0.approve(address(swapRouter), type(uint256).max);
        _token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        _token1.mint(address(this), 1000 ether);
        _token1.approve(address(swapRouter), type(uint256).max);
        _token1.approve(address(modifyLiquidityRouter), type(uint256).max);

        // addLiquidity(pk, _l_Tick, _u_Tick);
    }

    function addLiquidity(
        PoolKey memory poolKey,
        int24 _l_Tick,
        int24 _u_Tick
    ) internal {
        uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(_l_Tick);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(_u_Tick);

        uint256 ethToAdd = 1 ether;

        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(
            sqrtPriceAtTickLower,
            SQRT_PRICE_1_1,
            ethToAdd
        );
        uint256 tokenToAdd = LiquidityAmounts.getAmount1ForLiquidity(
            sqrtPriceAtTickLower,
            SQRT_PRICE_1_1,
            liquidityDelta
        );

        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: _l_Tick,
                tickUpper: _u_Tick,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ""
        );
    }

    function setUp() public {
        deployFreshManagerAndRouters();

        //Let's simulate a few tokens.
        token0 = new MockERC20("USDC", "USDC", 18);
        token1 = new MockERC20("WBTC", "WBTC", 18);
        token2 = new MockERC20("WSOL", "WSOL", 18);

        uint160 flags = (Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

        IFlashConnector cn = new DummyConnector();

        deployCodeTo("Fishstick.sol", abi.encode(manager, cn), address(flags));
        hook = FishstickHook(address(flags));

        //TODO: Set ranges that better reprsent actual values
        pk0 = tokenConfiguration(token0, token1, -60, 60, hook); //USD - WBTC
        pk1 = tokenConfiguration(token0, token2, -60, 60, hook); // USD - WSOL

        Currency.wrap(address(token0)).transfer(address(cn), 100 ether);
        Currency.wrap(address(token1)).transfer(address(cn), 100 ether);

        Currency.wrap(address(token0)).transfer(address(hook), 100 ether);
        Currency.wrap(address(token1)).transfer(address(hook), 100 ether);
    }

    function test_Swap_Empty_Success() public {
        uint128 liquidity = manager.getLiquidity(pk0.toId());
        // assertEq(liquidity, 0);

        uint256 balance0 = Currency.wrap(address(token0)).balanceOfSelf();
        uint256 balance1 = Currency.wrap(address(token1)).balanceOfSelf();
        console.log("Test balance");
        console.log(balance0, balance1);

        FlashLoanHookData memory data = FlashLoanHookData({
            connector: address(0),
            desiredAmount0: 100 ether,
            desiredAmount1: 100 ether,
            spread: 0.05e18,
            caller: alice
        });

        swap(pk0, true, -1 ether, abi.encode(data));

        balance0 = Currency.wrap(address(token0)).balanceOfSelf();
        balance1 = Currency.wrap(address(token1)).balanceOfSelf();
        console.log("Result");
        console.log(balance0, balance1);

        // uint128 liquidity = manager.getLiquidity(pk0.toId());
        // assertEq(liquidity, 0);
    }
}
