// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "./Voting.t.sol";
import {StakerYieldToken} from "../src/v2/StakerYieldToken.sol";
import {YieldCurveHookV2} from "../src/v2/YieldCurveHookV2.sol";
import {YieldCurveFactoryV2} from "../src/v2/YieldCurveFactoryV2.sol";
import {YieldSwapRouter} from "../src/uniswap/YieldSwapRouter.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract YieldCurveV2Test is Test {
    address constant ALICE = address(0xA11CE);
    uint256 constant ANCHOR = 1e17;
    uint256 constant SLOPE = 5e6;
    uint256 constant MIN_RATE = 5e16;
    uint256 constant MAX_RATE = 2e17;
    MockUSDC usdc;
    StakerYieldToken yt;
    PoolManager manager;
    YieldCurveHookV2 hook;
    YieldSwapRouter router;
    PoolKey key;
    uint64 maturity;

    function setUp() public {
        usdc = new MockUSDC();
        maturity = uint64(block.timestamp + 30 days);
        yt = new StakerYieldToken(usdc, address(this), maturity);
        yt.mint(address(this), 1_000_000_000);
        manager = new PoolManager(address(this));
        YieldCurveHookV2 implementation = new YieldCurveHookV2(
            IPoolManager(address(manager)), usdc, yt, maturity, 3000, ANCHOR, SLOPE, MIN_RATE, MAX_RATE
        );
        address hookAddress = address(uint160(implementation.REQUIRED_FLAGS()));
        vm.etch(hookAddress, address(implementation).code);
        hook = YieldCurveHookV2(hookAddress);
        address c0 = address(usdc) < address(yt) ? address(usdc) : address(yt);
        address c1 = address(usdc) < address(yt) ? address(yt) : address(usdc);
        key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 0, 1, IHooks(hookAddress));
        hook.configurePool(key);
        manager.initialize(key, 1 << 96);
        router = new YieldSwapRouter(IPoolManager(address(manager)));
        usdc.mint(address(this), 50_000_000);
        usdc.mint(ALICE, 20_000_000);
        usdc.approve(address(hook), type(uint256).max);
        yt.approve(address(hook), type(uint256).max);
        hook.addLiquidity(50_000_000, 500_000_000, 1);
        vm.prank(ALICE);
        usdc.approve(address(router), type(uint256).max);
        vm.prank(ALICE);
        yt.approve(address(router), type(uint256).max);
    }

    function testQuotesMatchRealV4SwapsAndRateMoves() public {
        uint256 rateBefore = hook.impliedRateWad();
        uint256 quote = hook.quoteBuy(1_000_000);
        vm.prank(ALICE);
        uint256 bought = router.swapExactInput(
            key, address(usdc) < address(yt), 1_000_000, quote, uint64(block.timestamp + 1 hours)
        );
        assertEq(bought, quote);
        assertGt(hook.impliedRateWad(), rateBefore);
        uint256 quoteSell = hook.quoteSell(bought / 2);
        vm.prank(ALICE);
        uint256 sold = router.swapExactInput(
            key, address(yt) < address(usdc), bought / 2, quoteSell, uint64(block.timestamp + 1 hours)
        );
        assertEq(sold, quoteSell);
        assertLt(hook.impliedRateWad(), rateBefore + SLOPE * bought);
        assertGe(hook.impliedRateWad(), MIN_RATE);
        assertLe(hook.impliedRateWad(), MAX_RATE);
    }

    function testPriceDecaysWithoutTradesAndMaturityStopsSwaps() public {
        uint256 rate = hook.impliedRateWad();
        uint256 first = hook.quoteSell(10_000_000);
        uint256 spot = hook.spotPriceWad();
        vm.warp(maturity - 1 days);
        assertEq(hook.impliedRateWad(), rate);
        assertLt(hook.quoteSell(10_000_000), first);
        assertLt(hook.spotPriceWad(), spot);
        vm.warp(maturity);
        assertEq(hook.spotPriceWad(), 0);
        vm.expectRevert();
        hook.quoteSell(10_000_000);
        vm.expectRevert();
        hook.addLiquidity(1, 1, 1);
        hook.removeLiquidity(hook.shares().balanceOf(address(this)), 0, 0);
    }

    function testRateBoundaryAndSlippageRevert() public {
        vm.expectRevert();
        hook.quoteSell(100_000_000_000);
        uint256 quote = hook.quoteBuy(1_000_000);
        vm.expectRevert();
        vm.prank(ALICE);
        router.swapExactInput(key, address(usdc) < address(yt), 1_000_000, quote + 1, uint64(block.timestamp + 1 hours));
    }

    function testFuzzQuoteAndRoundTrip(uint256 rawInput, uint256 rawWait) public {
        uint256 input = bound(rawInput, 10_000, 1_000_000);
        vm.warp(block.timestamp + bound(rawWait, 0, 15 days));
        uint256 quote = hook.quoteBuy(input);
        vm.prank(ALICE);
        uint256 bought =
            router.swapExactInput(key, address(usdc) < address(yt), input, quote, uint64(block.timestamp + 1 hours));
        assertEq(bought, quote);
        uint256 sellQuote = hook.quoteSell(bought);
        vm.prank(ALICE);
        uint256 received = router.swapExactInput(
            key, address(yt) < address(usdc), bought, sellQuote, uint64(block.timestamp + 1 hours)
        );
        assertEq(received, sellQuote);
        assertLe(received, input, "round trip must not create collateral");
        assertEq(hook.impliedRateWad(), ANCHOR, "net position restored");
    }

    function testMinedFactoryCreatesWorkingPool() public {
        YieldCurveFactoryV2 factory = new YieldCurveFactoryV2(address(this));
        bytes32 initHash = keccak256(
            abi.encodePacked(
                type(YieldCurveHookV2).creationCode,
                abi.encode(
                    IPoolManager(address(manager)), usdc, yt, maturity, uint24(3000), ANCHOR, SLOPE, MIN_RATE, MAX_RATE
                )
            )
        );
        uint160 flags = hook.REQUIRED_FLAGS();
        bytes32 salt;
        address predicted;
        bool found;
        for (uint256 i; i < 300_000; ++i) {
            salt = bytes32(i);
            predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, initHash)))));
            if ((uint160(predicted) & Hooks.ALL_HOOK_MASK) == flags) {
                found = true;
                break;
            }
        }
        assertTrue(found);
        YieldCurveHookV2 actual = factory.deployAndInitialize(
            IPoolManager(address(manager)), usdc, yt, maturity, 3000, ANCHOR, SLOPE, MIN_RATE, MAX_RATE, salt
        );
        assertEq(address(actual), predicted);
        usdc.mint(address(this), 10_000_000);
        usdc.approve(address(actual), type(uint256).max);
        yt.approve(address(actual), type(uint256).max);
        actual.addLiquidity(10_000_000, 100_000_000, 1);
        assertGt(actual.quoteSell(1_000_000), 0);
    }
}
