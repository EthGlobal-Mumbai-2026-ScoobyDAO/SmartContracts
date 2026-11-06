// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "./Voting.t.sol";
import {MockCCIPRouter} from "./CCIP.t.sol";
import {ReportRegistry} from "../src/ReportRegistry.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";
import {StakerYieldToken} from "../src/v2/StakerYieldToken.sol";
import {YieldCurveHookV2} from "../src/v2/YieldCurveHookV2.sol";
import {StakeAndSellRouterV2} from "../src/v2/StakeAndSellRouterV2.sol";
import {CCIPStakeSenderV2} from "../src/v2/CCIPStakeSenderV2.sol";
import {CCIPStakeReceiverV2} from "../src/v2/CCIPStakeReceiverV2.sol";
import {StakeIntentV2} from "../src/v2/StakeIntentV2.sol";
import {YieldSwapRouter} from "../src/uniswap/YieldSwapRouter.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @notice Eight independently funded voters exercise the complete local V2 lifecycle.
contract EightVoterWorkflowV2Test is Test {
    uint256 constant REVIEWER_KEY = 0xA11CE;
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant CAROL = address(0xCA401);
    address constant DAVE = address(0xDA0E);
    address constant EVE = address(0xE0E);
    address constant FRANK = address(0xF12A);
    address constant GRACE = address(0x6ACE);
    address constant HEIDI = address(0x4E1D1);
    address constant TREASURY = address(0x7EA5);

    MockUSDC usdc;
    ReportRegistry registry;
    RiskFiStakeVaultV2 vault;
    StakerYieldToken yt;
    PoolManager manager;
    YieldCurveHookV2 hook;
    YieldSwapRouter swapRouter;
    StakeAndSellRouterV2 atomicRouter;
    MockCCIPRouter ccipRouter;
    CCIPStakeSenderV2 ccipSender;
    CCIPStakeReceiverV2 ccipReceiver;
    PoolKey key;
    uint256 reportId;
    uint64 lockTime;

    function setUp() public {
        usdc = new MockUSDC();
        registry = new ReportRegistry(address(this));
        vault = new RiskFiStakeVaultV2(usdc, registry, address(this), TREASURY);
        lockTime = uint64(block.timestamp + 2 days);
        ReportRegistry.Report memory r = ReportRegistry.Report({
            reportHash: keccak256("eight-voter evidence report"),
            claimHash: keccak256("precise 30-day demo claim"),
            reviewer: vm.addr(REVIEWER_KEY),
            resolver: address(this),
            adjudicator: address(this),
            lockTime: lockTime,
            crossChainCutoff: uint64(lockTime - 1 days),
            resultDeadline: uint64(uint256(lockTime) + 33 days),
            challengePeriod: 1 days
        });
        uint64 approvalExpiry = uint64(block.timestamp + 1 days);
        (uint8 v, bytes32 a, bytes32 b) = vm.sign(REVIEWER_KEY, registry.approvalDigest(r, 1, approvalExpiry));
        reportId = registry.publish(r, 1, approvalExpiry, abi.encodePacked(a, b, v));
        vault.initializeSeries(reportId);
        yt = vault.yt();

        manager = new PoolManager(address(this));
        YieldCurveHookV2 implementation = new YieldCurveHookV2(
            IPoolManager(address(manager)), usdc, yt, vault.maturity(), 3000, 1e17, 5e6, 5e16, 2e17
        );
        address hookAddress = address(uint160(implementation.REQUIRED_FLAGS()));
        vm.etch(hookAddress, address(implementation).code);
        hook = YieldCurveHookV2(hookAddress);
        address c0 = address(usdc) < address(yt) ? address(usdc) : address(yt);
        address c1 = address(usdc) < address(yt) ? address(yt) : address(usdc);
        key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 0, 1, IHooks(hookAddress));
        hook.configurePool(key);
        manager.initialize(key, 1 << 96);
        swapRouter = new YieldSwapRouter(IPoolManager(address(manager)));
        atomicRouter = new StakeAndSellRouterV2(vault, hook, swapRouter, key);
        ccipRouter = new MockCCIPRouter();
        ccipReceiver = new CCIPStakeReceiverV2(address(ccipRouter), ccipRouter.SOURCE(), usdc, vault, address(this));
        ccipSender = new CCIPStakeSenderV2(ccipRouter, usdc, 98765, address(ccipReceiver));
        ccipReceiver.configureSourceSender(address(ccipSender));
        ccipSender.configureReportCutoff(reportId, uint64(lockTime - 1 days));

        _fundVoter(ALICE, 81_000_000);
        _fundVoter(BOB, 40_000_000);
        _fundVoter(CAROL, 40_000_000);
        _fundVoter(DAVE, 20_000_000);
        _fundVoter(EVE, 20_000_000);
        _fundVoter(FRANK, 15_000_000);
        _fundVoter(GRACE, 10_000_000);
        _fundVoter(HEIDI, 5_000_000);
        usdc.mint(address(this), 33_000_000);
        usdc.approve(address(vault), type(uint256).max);
    }

    function _fundVoter(address person, uint256 amount) internal {
        usdc.mint(person, amount);
        vm.startPrank(person);
        usdc.approve(address(vault), type(uint256).max);
        usdc.approve(address(atomicRouter), type(uint256).max);
        usdc.approve(address(swapRouter), type(uint256).max);
        usdc.approve(address(ccipSender), type(uint256).max);
        vm.stopPrank();
    }

    function _keep(address person, bool yes, uint256 amount) internal {
        vm.prank(person);
        vault.stake(reportId, yes, amount, person, person);
        assertEq(vault.positionOf(person, yes), amount);
        assertEq(yt.balanceOf(person), amount);
    }

    function _sellOnStake(address person, bool yes, uint256 amount) internal returns (uint256 received) {
        uint256 quote = atomicRouter.quoteSell(amount);
        vm.prank(person);
        received = atomicRouter.stakeAndSellYield(yes, amount, quote, uint64(block.timestamp + 1 hours));
        assertEq(received, quote);
        assertGt(received, 0);
        assertEq(vault.positionOf(person, yes), amount);
        assertEq(yt.balanceOf(person), 0);
    }

    function _claimYT(address person) internal returns (uint256 amount) {
        vm.prank(person);
        amount = yt.claimYield();
    }

    function _remoteKeep(address person, bool yes, uint256 amount) internal {
        StakeIntentV2 memory intent =
            StakeIntentV2(2, reportId, yes, person, person, 9, uint64(lockTime + 1 days), amount);
        vm.prank(person);
        bytes32 messageId = ccipSender.stakeRemote(intent, amount, "");
        assertTrue(ccipReceiver.delivered(messageId));
        assertEq(ccipReceiver.recoverable(messageId), 0);
        assertEq(vault.positionOf(person, yes), amount);
        assertEq(yt.balanceOf(person), amount);
    }

    function testEightVotersFromApprovalThroughYieldTradingAndVerdict() public {
        // Carol stakes first and contributes her YT plus separate dUSD liquidity.
        _keep(CAROL, true, 30_000_000);
        vm.startPrank(CAROL);
        usdc.approve(address(hook), type(uint256).max);
        yt.approve(address(hook), type(uint256).max);
        hook.addLiquidity(10_000_000, 30_000_000, 1);
        vm.stopPrank();

        _keep(ALICE, true, 80_000_000);
        _sellOnStake(BOB, false, 40_000_000);
        _keep(DAVE, false, 20_000_000);
        _sellOnStake(EVE, true, 20_000_000);
        _keep(FRANK, false, 15_000_000);
        _keep(GRACE, true, 10_000_000);
        _remoteKeep(HEIDI, true, 5_000_000);
        assertEq(vault.totalYes(), 145_000_000);
        assertEq(vault.totalNo(), 75_000_000);
        assertEq(yt.totalSupply(), 220_000_000);
        assertEq(usdc.balanceOf(address(vault)), 220_000_000);
        assertEq(registry.reportCount(), 1);

        // First period: each current YT holder earns 0.10 dUSD per YT.
        vm.warp(block.timestamp + 1 days);
        vault.injectYield(22_000_000);
        uint256 yieldClaimed;
        vm.prank(CAROL);
        uint256 firstLPYield = hook.claimLPYield();
        assertLe(firstLPYield, 9_000_000);
        assertLe(9_000_000 - firstLPYield, 1, "LP share rounding");
        yieldClaimed += firstLPYield;
        assertEq(_claimYT(ALICE), 8_000_000);
        yieldClaimed += 8_000_000;
        assertEq(_claimYT(DAVE), 2_000_000);
        yieldClaimed += 2_000_000;
        assertEq(_claimYT(FRANK), 1_500_000);
        yieldClaimed += 1_500_000;
        assertEq(_claimYT(GRACE), 1_000_000);
        yieldClaimed += 1_000_000;
        assertEq(_claimYT(BOB), 0);
        assertEq(_claimYT(EVE), 0);

        // Alice buys future YT through v4. She cannot take Carol's earlier LP yield.
        vm.warp(block.timestamp + 10 days);
        vm.prank(ALICE);
        usdc.approve(address(swapRouter), type(uint256).max);
        uint256 buyQuote = hook.quoteBuy(200_000);
        vm.prank(ALICE);
        uint256 bought = swapRouter.swapExactInput(
            key, address(usdc) < address(yt), 200_000, buyQuote, uint64(block.timestamp + 1 hours)
        );
        assertEq(bought, buyQuote);
        assertEq(_claimYT(ALICE), 0, "buyer cannot take first-period accrual");

        // Second period: 0.05 dUSD per outstanding YT, apportioned by holdings.
        vault.injectYield(11_000_000);
        vm.prank(CAROL);
        yieldClaimed += hook.claimLPYield();
        yieldClaimed += _claimYT(ALICE);
        yieldClaimed += _claimYT(DAVE);
        yieldClaimed += _claimYT(FRANK);
        yieldClaimed += _claimYT(GRACE);

        // The claim clock is real: verdict only after lock + 30 days.
        vm.expectRevert();
        vault.propose(RiskFiStakeVaultV2.Outcome.Yes, keccak256("early"));
        vm.warp(uint256(lockTime) + 30 days);
        vault.propose(RiskFiStakeVaultV2.Outcome.No, keccak256("initial verdict"));
        vault.challenge(keccak256("counterevidence"));
        vm.expectRevert();
        vault.finalize();
        vault.adjudicate(RiskFiStakeVaultV2.Outcome.Yes, keccak256("reviewed evidence"));
        assertEq(uint256(vault.finalOutcome()), uint256(RiskFiStakeVaultV2.Outcome.Yes));
        yieldClaimed += _claimYT(HEIDI); // Matured YT keeps previously accrued yield.
        assertLe(yieldClaimed, 33_000_000);
        assertLe(33_000_000 - yieldClaimed, 10, "bounded yield rounding dust");

        uint256 winnerPaid;
        vm.prank(ALICE);
        winnerPaid += vault.claimPrincipal(true, 80_000_000);
        vm.prank(CAROL);
        winnerPaid += vault.claimPrincipal(true, 30_000_000);
        vm.prank(EVE);
        winnerPaid += vault.claimPrincipal(true, 20_000_000);
        vm.prank(GRACE);
        winnerPaid += vault.claimPrincipal(true, 10_000_000);
        vm.prank(HEIDI);
        winnerPaid += vault.claimPrincipal(true, 5_000_000);
        vm.prank(BOB);
        assertEq(vault.claimPrincipal(false, 40_000_000), 0);
        vm.prank(DAVE);
        assertEq(vault.claimPrincipal(false, 20_000_000), 0);
        vm.prank(FRANK);
        assertEq(vault.claimPrincipal(false, 15_000_000), 0);
        assertEq(vault.claimFee(), 15_000_000);
        assertLe(winnerPaid + 15_000_000, 220_000_000);
        assertLe(220_000_000 - winnerPaid - 15_000_000, 5, "bounded principal rounding dust");
        vm.expectRevert();
        vm.prank(ALICE);
        vault.claimPrincipal(true, 1);

        // LPs can exit after maturity; remaining principal dust is swept at expiry.
        uint256 carolShares = hook.shares().balanceOf(CAROL);
        vm.prank(CAROL);
        hook.removeLiquidity(carolShares, 0, 0);
        vm.warp(uint256(vault.finalizedAt()) + 90 days + 1);
        vault.sweepDust();
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertLe(usdc.balanceOf(address(hook)), 2, "bounded LP index dust");
        assertEq(usdc.balanceOf(address(atomicRouter)), 0);
        assertEq(usdc.balanceOf(address(swapRouter)), 0);
        assertEq(usdc.balanceOf(address(manager)), 0);

        uint256 accounted = usdc.balanceOf(ALICE) + usdc.balanceOf(BOB) + usdc.balanceOf(CAROL) + usdc.balanceOf(DAVE)
            + usdc.balanceOf(EVE) + usdc.balanceOf(FRANK) + usdc.balanceOf(GRACE) + usdc.balanceOf(HEIDI)
            + usdc.balanceOf(TREASURY) + usdc.balanceOf(address(hook)) + usdc.balanceOf(address(yt))
            + usdc.balanceOf(address(this));
        assertEq(accounted, 264_000_000, "all 231 dUSD collateral/liquidity and 33 dUSD simulated yield accounted");
    }

    function testCCIPFundedV2YTCanTradeOnUniswap() public {
        _keep(CAROL, true, 30_000_000);
        vm.startPrank(CAROL);
        usdc.approve(address(hook), type(uint256).max);
        yt.approve(address(hook), type(uint256).max);
        hook.addLiquidity(10_000_000, 30_000_000, 1);
        vm.stopPrank();
        _remoteKeep(HEIDI, true, 5_000_000);
        uint256 quote = hook.quoteSell(5_000_000);
        vm.startPrank(HEIDI);
        yt.approve(address(swapRouter), 5_000_000);
        uint256 proceeds = swapRouter.swapExactInput(
            key, address(yt) < address(usdc), 5_000_000, quote, uint64(block.timestamp + 1 hours)
        );
        vm.stopPrank();
        assertEq(proceeds, quote);
        assertEq(yt.balanceOf(HEIDI), 0);
        assertEq(vault.positionOf(HEIDI, true), 5_000_000);
        assertEq(usdc.balanceOf(HEIDI), proceeds);
        assertEq(usdc.balanceOf(address(vault)), 35_000_000);
    }
}
