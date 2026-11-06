// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "./Voting.t.sol";
import {StakerYieldToken} from "../src/v2/StakerYieldToken.sol";
import {YieldCurveHookV2} from "../src/v2/YieldCurveHookV2.sol";
import {YieldCurveFactoryV2} from "../src/v2/YieldCurveFactoryV2.sol";
import {YieldSwapRouter} from "../src/uniswap/YieldSwapRouter.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @notice Executes a V2 swap against Sepolia's actual PoolManager in a local fork.
/// No transaction is broadcast to the network.
contract V2LivePoolForkTest is Test {
    uint256 constant ANCHOR = 1e17;
    uint256 constant SLOPE = 5e6;
    uint256 constant MIN_RATE = 5e16;
    uint256 constant MAX_RATE = 2e17;

    function _deployHook(IPoolManager manager, MockUSDC usdc, StakerYieldToken yt, uint64 maturity)
        internal
        returns (YieldCurveHookV2 hook)
    {
        YieldCurveFactoryV2 factory = new YieldCurveFactoryV2(address(this));
        bytes32 initHash = keccak256(
            abi.encodePacked(
                type(YieldCurveHookV2).creationCode,
                abi.encode(manager, usdc, yt, maturity, uint24(3000), ANCHOR, SLOPE, MIN_RATE, MAX_RATE)
            )
        );
        uint160 flags = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;
        bytes32 salt;
        bool found;
        for (uint256 i; i < 300_000; ++i) {
            salt = bytes32(i);
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, initHash)))));
            if ((uint160(predicted) & Hooks.ALL_HOOK_MASK) == flags) {
                found = true;
                break;
            }
        }
        assertTrue(found);
        hook = factory.deployAndInitialize(manager, usdc, yt, maturity, 3000, ANCHOR, SLOPE, MIN_RATE, MAX_RATE, salt);
    }

    function testForkedSepoliaPoolManagerBuysAndSellsYT() public {
        string memory rpc = vm.envOr("ETH_SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        IPoolManager manager = IPoolManager(vm.envAddress("SEPOLIA_V4_POOL_MANAGER"));
        assertGt(address(manager).code.length, 0);
        MockUSDC usdc = new MockUSDC();
        uint64 maturity = uint64(block.timestamp + 30 days);
        StakerYieldToken yt = new StakerYieldToken(usdc, address(this), maturity);
        yt.mint(address(this), 1_000_000_000);
        YieldCurveHookV2 hook = _deployHook(manager, usdc, yt, maturity);
        usdc.mint(address(this), 52_000_000);
        usdc.approve(address(hook), type(uint256).max);
        yt.approve(address(hook), type(uint256).max);
        hook.addLiquidity(50_000_000, 500_000_000, 1);
        YieldSwapRouter router = new YieldSwapRouter(manager);
        usdc.approve(address(router), type(uint256).max);
        yt.approve(address(router), type(uint256).max);
        address c0 = address(usdc) < address(yt) ? address(usdc) : address(yt);
        address c1 = address(usdc) < address(yt) ? address(yt) : address(usdc);
        PoolKey memory key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 0, 1, IHooks(address(hook)));
        uint256 quote = hook.quoteBuy(1_000_000);
        uint256 bought = router.swapExactInput(
            key, address(usdc) < address(yt), 1_000_000, quote, uint64(block.timestamp + 1 hours)
        );
        assertEq(bought, quote);
        uint256 sellQuote = hook.quoteSell(bought);
        uint256 sold = router.swapExactInput(
            key, address(yt) < address(usdc), bought, sellQuote, uint64(block.timestamp + 1 hours)
        );
        assertEq(sold, sellQuote);
        assertLe(sold, 1_000_000);
    }
}
