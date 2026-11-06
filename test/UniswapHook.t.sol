// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "./Voting.t.sol";
import {YieldToken} from "../src/yield/YieldToken.sol";
import {YieldMarketHook} from "../src/uniswap/YieldMarketHook.sol";
import {YieldSwapRouter} from "../src/uniswap/YieldSwapRouter.sol";
import {YieldLPShare} from "../src/uniswap/YieldLPShare.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract UniswapHookTest is Test {
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    MockUSDC usdc;
    YieldToken yt;
    PoolManager manager;
    YieldMarketHook hook;
    YieldSwapRouter router;
    PoolKey key;
    uint64 maturity;

    function setUp() public {
        usdc = new MockUSDC();
        yt = new YieldToken(usdc, address(this), "Test YT", "YT");
        yt.mint(address(this), 1_000_000_000);
        manager = new PoolManager(address(this));
        maturity = uint64(block.timestamp + 30 days);
        YieldMarketHook implementation = new YieldMarketHook(IPoolManager(address(manager)), usdc, yt, maturity, 3000);
        address hookAddress = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG)
        );
        vm.etch(hookAddress, address(implementation).code);
        hook = YieldMarketHook(hookAddress);
        address c0 = address(usdc) < address(yt) ? address(usdc) : address(yt);
        address c1 = address(usdc) < address(yt) ? address(yt) : address(usdc);
        key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 0, 1, IHooks(hookAddress));
        hook.configurePool(key);
        manager.initialize(key, 1 << 96);
        router = new YieldSwapRouter(IPoolManager(address(manager)));
        usdc.mint(address(this), 500_000_000);
        usdc.mint(ALICE, 200_000_000);
        usdc.mint(BOB, 200_000_000);
        usdc.approve(address(hook), type(uint256).max);
        yt.approve(address(hook), type(uint256).max);
        hook.addLiquidity(500_000_000, 500_000_000, 500_000_000);
        vm.prank(ALICE);
        usdc.approve(address(router), type(uint256).max);
        vm.prank(ALICE);
        yt.approve(address(router), type(uint256).max);
        vm.prank(BOB);
        usdc.approve(address(router), type(uint256).max);
    }

    function _buy(address trader, uint256 amount) internal returns (uint256 output) {
        bool zeroForOne = address(usdc) < address(yt);
        vm.prank(trader);
        output = router.swapExactInput(key, zeroForOne, amount, 1, uint64(block.timestamp + 1 hours));
    }

    function _sell(address trader, uint256 amount) internal returns (uint256 output) {
        bool zeroForOne = address(yt) < address(usdc);
        vm.prank(trader);
        output = router.swapExactInput(key, zeroForOne, amount, 1, uint64(block.timestamp + 1 hours));
    }

    function testActualPoolManagerBuySellAndLPYield() public {
        uint256 bought = _buy(ALICE, 100_000_000);
        assertGt(bought, 0);
        assertEq(yt.balanceOf(ALICE), bought);
        usdc.mint(address(yt), 10_000_000);
        yt.notifyYield(10_000_000);
        uint256 lpYield = hook.claimLPYield();
        assertGt(lpYield, 0);
        uint256 aliceYield = yt.unclaimedUSDC(ALICE);
        assertEq(aliceYield, 0); // lazy checkpoint
        vm.prank(ALICE);
        yt.claimYield();
        assertGt(usdc.balanceOf(ALICE), 100_000_000);
        uint256 sold = _sell(ALICE, bought / 2);
        assertGt(sold, 0);
        assertEq(
            hook.usdcReserve() + usdc.balanceOf(address(this)) + usdc.balanceOf(ALICE) + usdc.balanceOf(BOB)
                + hook.lpYieldReserved() + usdc.balanceOf(address(yt)),
            910_000_000
        );
        vm.warp(maturity);
        vm.expectRevert();
        _buy(BOB, 1_000_000);
        YieldLPShare shares = hook.shares();
        hook.removeLiquidity(shares.balanceOf(address(this)), 0, 0);
    }

    function testTwoYieldPeriodsTraderAndLPAttribution() public {
        uint256 aliceBought = _buy(ALICE, 100_000_000);
        usdc.mint(address(yt), 10_000_000);
        yt.notifyYield(10_000_000);
        uint256 lpFirst = hook.claimLPYield();
        assertGt(lpFirst, 0);
        uint256 aliceFirst;
        vm.prank(ALICE);
        aliceFirst = yt.claimYield();
        assertGt(aliceFirst, 0);
        uint256 sold = _sell(ALICE, aliceBought / 2);
        assertGt(sold, 0);
        uint256 bobBought = _buy(BOB, 50_000_000);
        assertGt(bobBought, 0);
        vm.prank(BOB);
        assertEq(yt.claimYield(), 0, "Bob cannot take first period");
        YieldLPShare lp = hook.shares();
        lp.transfer(BOB, lp.balanceOf(address(this)) / 2);
        vm.prank(BOB);
        assertEq(hook.claimLPYield(), 0, "new LP cannot take first period");
        usdc.mint(address(yt), 15_000_000);
        yt.notifyYield(15_000_000);
        uint256 claimed = lpFirst + aliceFirst;
        claimed += hook.claimLPYield();
        vm.prank(BOB);
        claimed += hook.claimLPYield();
        vm.prank(ALICE);
        claimed += yt.claimYield();
        vm.prank(BOB);
        claimed += yt.claimYield();
        claimed += yt.claimYield();
        assertLe(claimed, 25_000_000, "no yield created");
        assertLe(25_000_000 - claimed, 10, "only rounding dust");
        vm.prank(BOB);
        assertEq(hook.claimLPYield(), 0, "double LP claim");
        vm.prank(ALICE);
        assertEq(yt.claimYield(), 0, "double YT claim");
    }
}
