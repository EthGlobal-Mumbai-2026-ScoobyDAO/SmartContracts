// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "./Voting.t.sol";
import {ReportRegistry} from "../src/ReportRegistry.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";
import {StakerYieldToken} from "../src/v2/StakerYieldToken.sol";
import {YieldCurveHookV2} from "../src/v2/YieldCurveHookV2.sol";
import {StakeAndSellRouterV2} from "../src/v2/StakeAndSellRouterV2.sol";
import {YieldSwapRouter} from "../src/uniswap/YieldSwapRouter.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract StakeAndSellV2Test is Test {
    uint256 constant REVIEWER_KEY = 0xA11CE;
    address constant LP = address(0xB0B);
    address constant ALICE = address(0xA11CE);
    address constant TREASURY = address(0x7EA5);
    MockUSDC usdc;
    ReportRegistry registry;
    RiskFiStakeVaultV2 vault;
    StakerYieldToken yt;
    PoolManager manager;
    YieldCurveHookV2 hook;
    YieldSwapRouter swapRouter;
    StakeAndSellRouterV2 atomicRouter;
    uint256 id;
    uint64 lockTime;

    function setUp() public {
        usdc = new MockUSDC();
        registry = new ReportRegistry(address(this));
        vault = new RiskFiStakeVaultV2(usdc, registry, address(this), TREASURY);
        lockTime = uint64(block.timestamp + 2 days);
        ReportRegistry.Report memory r = ReportRegistry.Report({
            reportHash: keccak256("atomic demo report"),
            claimHash: keccak256("atomic demo claim"),
            reviewer: vm.addr(REVIEWER_KEY),
            resolver: address(this),
            adjudicator: address(this),
            lockTime: lockTime,
            crossChainCutoff: uint64(lockTime - 1 days),
            resultDeadline: uint64(uint256(lockTime) + 33 days),
            challengePeriod: 1 days
        });
        uint64 expiry = uint64(block.timestamp + 1 days);
        (uint8 v, bytes32 a, bytes32 b) = vm.sign(REVIEWER_KEY, registry.approvalDigest(r, 1, expiry));
        id = registry.publish(r, 1, expiry, abi.encodePacked(a, b, v));
        vault.initializeSeries(id);
        yt = vault.yt();
        manager = new PoolManager(address(this));
        uint64 maturity = vault.maturity();
        YieldCurveHookV2 implementation =
            new YieldCurveHookV2(IPoolManager(address(manager)), usdc, yt, maturity, 3000, 1e17, 5e6, 5e16, 2e17);
        address hookAddress = address(uint160(implementation.REQUIRED_FLAGS()));
        vm.etch(hookAddress, address(implementation).code);
        hook = YieldCurveHookV2(hookAddress);
        address c0 = address(usdc) < address(yt) ? address(usdc) : address(yt);
        address c1 = address(usdc) < address(yt) ? address(yt) : address(usdc);
        PoolKey memory key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 0, 1, IHooks(hookAddress));
        hook.configurePool(key);
        manager.initialize(key, 1 << 96);
        swapRouter = new YieldSwapRouter(IPoolManager(address(manager)));
        atomicRouter = new StakeAndSellRouterV2(vault, hook, swapRouter, key);

        usdc.mint(LP, 550_000_000);
        usdc.mint(ALICE, 80_000_000);
        usdc.mint(address(this), 10_000_000);
        vm.startPrank(LP);
        usdc.approve(address(vault), type(uint256).max);
        vault.stake(id, false, 500_000_000, LP, LP);
        usdc.approve(address(hook), type(uint256).max);
        yt.approve(address(hook), type(uint256).max);
        hook.addLiquidity(50_000_000, 500_000_000, 1);
        vm.stopPrank();
        vm.prank(ALICE);
        usdc.approve(address(atomicRouter), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
    }

    function testAtomicStakeSellYieldAndSettlePrincipal() public {
        uint256 quote = atomicRouter.quoteSell(80_000_000);
        vm.prank(ALICE);
        uint256 received = atomicRouter.stakeAndSellYield(true, 80_000_000, quote, uint64(block.timestamp + 1 hours));
        assertEq(received, quote);
        assertEq(usdc.balanceOf(ALICE), quote, "cash now");
        assertEq(vault.positionOf(ALICE, true), 80_000_000, "verdict position retained");
        assertEq(yt.balanceOf(ALICE), 0, "YT sold");
        assertEq(yt.balanceOf(address(hook)), 580_000_000, "hook holds purchased YT");
        vault.injectYield(10_000_000);
        vm.prank(LP);
        uint256 lpYield = hook.claimLPYield();
        assertLe(lpYield, 10_000_000, "yield conservation");
        assertLe(10_000_000 - lpYield, 2, "only index rounding dust");
        vm.warp(uint256(lockTime) + 30 days);
        vault.propose(RiskFiStakeVaultV2.Outcome.Yes, keccak256("evidence"));
        vm.warp(block.timestamp + 1 days);
        vault.finalize();
        vm.prank(ALICE);
        assertEq(vault.claimPrincipal(true, 80_000_000), 480_000_000);
        assertEq(vault.claimFee(), 100_000_000);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function testSlippageRevertsEntireStake() public {
        uint256 quote = atomicRouter.quoteSell(80_000_000);
        vm.expectRevert();
        vm.prank(ALICE);
        atomicRouter.stakeAndSellYield(true, 80_000_000, quote + 1, uint64(block.timestamp + 1 hours));
        assertEq(vault.positionOf(ALICE, true), 0);
        assertEq(yt.totalSupply(), 500_000_000);
        assertEq(usdc.balanceOf(ALICE), 80_000_000);
    }
}
