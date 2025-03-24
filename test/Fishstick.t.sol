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
    MockERC20 token2; // MOCK

    PoolKey pk0;
    PoolKey pk1;

    Currency currency2;

    FishstickHook hook;

    address alice = makeAddr("ALICE");

    function tokenConfiguration(
        MockERC20 _token0,
        MockERC20 _token1
    ) internal {
        _token0.mint(address(this), 10000 ether);
        _token0.approve(address(swapRouter), type(uint256).max);
        _token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        _token1.mint(address(this), 10000 ether);
        _token1.approve(address(swapRouter), type(uint256).max);
        _token1.approve(address(modifyLiquidityRouter), type(uint256).max);
    }

    function createPool(
        Currency _currency0,
        Currency _currency1
    ) internal returns (PoolKey memory) {
        PoolKey memory pk = PoolKey(_currency0, _currency1, 3000, 60, hook);
        manager.initialize(pk, SQRT_PRICE_1_1);
        return pk;
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
        console.log("Alice", alice);

        deployFreshManagerAndRouters();

        //Let's simulate a few tokens.
        token0 = new MockERC20("USDC", "USDC", 18);
        token1 = new MockERC20("WBTC", "WBTC", 18);
        token2 = new MockERC20("MOCK", "MOCK", 18);
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));
        currency2 = Currency.wrap(address(token2));
        tokenConfiguration(token0, token1); //USD - WBTC
        tokenConfiguration(token0, token2); // USD - MOCK

        //Deploy Dummy connector and fund it
        IFlashConnector cn = new DummyConnector();
        currency0.transfer(address(cn), 100 ether);
        currency1.transfer(address(cn), 100 ether);

        //Deploy Fishstick hook
        uint160 flags = (Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        deployCodeTo("Fishstick.sol", abi.encode(manager, cn), address(flags));
        hook = FishstickHook(address(flags));

        //Create pools
        pk0 = createPool(currency0, currency1);
        pk1 = createPool(currency0, currency2);

        currency0.transfer(alice, 1000 ether);
        currency1.transfer(alice, 1000 ether);
        currency2.transfer(alice, 1000 ether);

        vm.startPrank(alice);
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);
        //todo: somehow sendToPoolManager requires an approve for transferFrom. investigate it further
        token0.approve(address(manager), type(uint256).max);
        token1.approve(address(manager), type(uint256).max);

        //approve PoolSwapTest
        token0.approve(0x2e234DAe75C793f67A35089C9d99245E1C58470b, type(uint256).max);
        token1.approve(0x2e234DAe75C793f67A35089C9d99245E1C58470b, type(uint256).max);

        //approve DummyConnector
        token0.approve(address(cn), type(uint256).max);
        token1.approve(address(cn), type(uint256).max);

        vm.stopPrank();
    }

    function test_Swap_Zero_For_One_Empty_Success() public {
        uint128 liquidity = manager.getLiquidity(pk0.toId());
        assertEq(liquidity, 0);

        uint256 initZeroBalance = currency0.balanceOf(alice);
        uint256 initOneBalance = currency1.balanceOf(alice);
        console.log("Initial balance");
        console.log(initZeroBalance, initOneBalance);

        FlashLoanHookData memory data = FlashLoanHookData({
            connector: address(0),
            desiredAmount0: 100 ether,
            desiredAmount1: 100 ether,
            spread: 0.05e18,
            caller: alice
        });

        vm.startPrank(alice);
        swap(pk0, true, -50 ether, abi.encode(data));
        vm.stopPrank();

        uint256 resultZeroBalance = currency0.balanceOf(alice);
        uint256 resultOneBalance = currency1.balanceOf(alice);
        console.log("Result balance");
        console.log(resultZeroBalance, resultOneBalance);

        liquidity = manager.getLiquidity(pk0.toId());
        assertEq(liquidity, 0);
    }
}
