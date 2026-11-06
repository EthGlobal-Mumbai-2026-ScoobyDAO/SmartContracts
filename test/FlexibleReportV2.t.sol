// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ReportRegistry} from "../src/ReportRegistry.sol";
import {FlexibleReportRegistry} from "../src/v2/FlexibleReportRegistry.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";
import {YieldCurveHookV2} from "../src/v2/YieldCurveHookV2.sol";
import {YieldSwapRouter} from "../src/uniswap/YieldSwapRouter.sol";
import {V2MockUSD} from "./helpers/V2Mocks.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract FlexibleReportV2Test is Test {
    uint256 constant REVIEWER_KEY = 0xA11CE;
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    FlexibleReportRegistry registry;
    RiskFiStakeVaultV2 vault;
    V2MockUSD usd;
    uint64 lockTime;
    uint64 maturityTime;
    uint64 resultDeadline;

    function setUp() public {
        usd = new V2MockUSD();
        registry = new FlexibleReportRegistry(address(this));
        vault = new RiskFiStakeVaultV2(usd, ReportRegistry(address(registry)), address(this), address(this));
        lockTime = uint64(block.timestamp + 10 minutes);
        maturityTime = uint64(block.timestamp + 50 minutes);
        resultDeadline = uint64(block.timestamp + 1 hours);
        usd.mint(ALICE, 100_000_001);
        usd.mint(BOB, 100_000_000);
        vm.prank(ALICE);
        usd.approve(address(vault), type(uint256).max);
        vm.prank(BOB);
        usd.approve(address(vault), type(uint256).max);
    }

    function report() internal view returns (FlexibleReportRegistry.Report memory) {
        return FlexibleReportRegistry.Report({
            reportHash: keccak256("accelerated demo report bytes"),
            claimHash: keccak256("accelerated demo claim"),
            reviewer: vm.addr(REVIEWER_KEY),
            resolver: address(this),
            adjudicator: address(this),
            lockTime: lockTime,
            crossChainCutoff: uint64(block.timestamp + 5 minutes),
            resultDeadline: resultDeadline,
            challengePeriod: 5 minutes
        });
    }

    function publish(FlexibleReportRegistry.Report memory r, uint64 maturity_, uint256 nonce)
        internal
        returns (uint256)
    {
        uint64 expiry = uint64(block.timestamp + 5 minutes);
        (uint8 v, bytes32 s1, bytes32 s2) = vm.sign(REVIEWER_KEY, registry.approvalDigest(r, maturity_, nonce, expiry));
        return registry.publish(r, maturity_, nonce, expiry, abi.encodePacked(s1, s2, v));
    }

    function testTenMinuteVoteAndOneHourSettlement() public {
        uint256 id = publish(report(), maturityTime, 1);
        vault.initializeSeries(id);
        assertEq(vault.maturity(), maturityTime);
        vm.prank(ALICE);
        vault.stake(id, true, 100_000_000, ALICE, ALICE);
        vm.prank(BOB);
        vault.stake(id, false, 100_000_000, BOB, BOB);
        vm.warp(lockTime);
        vm.expectRevert(bytes("CLOSED"));
        vm.prank(ALICE);
        vault.stake(id, true, 1, ALICE, ALICE);
        vm.expectRevert(bytes("RESOLVER"));
        vault.propose(RiskFiStakeVaultV2.Outcome.Yes, keccak256("early"));
        vm.warp(maturityTime);
        vault.propose(RiskFiStakeVaultV2.Outcome.Yes, keccak256("evidence"));
        vm.warp(maturityTime + 5 minutes);
        vault.finalize();
        assertLt(block.timestamp, resultDeadline);
        vm.prank(ALICE);
        assertEq(vault.claimPrincipal(true, 100_000_000), 180_000_000);
        vm.prank(BOB);
        assertEq(vault.claimPrincipal(false, 100_000_000), 0);
        assertEq(vault.claimFee(), 20_000_000);
    }

    function testClockValidationAndReviewerBinding() public {
        FlexibleReportRegistry.Report memory r = report();
        uint64 expiry = uint64(block.timestamp + 5 minutes);
        (uint8 v, bytes32 a, bytes32 b) = vm.sign(REVIEWER_KEY, registry.approvalDigest(r, maturityTime, 1, expiry));
        bytes memory signature = abi.encodePacked(a, b, v);
        vm.expectRevert(bytes("MATURITY"));
        registry.publish(r, lockTime, 1, expiry, signature);
        vm.expectRevert(bytes("REVIEWER"));
        registry.publish(r, maturityTime + 1, 1, expiry, signature);
        assertEq(registry.publish(r, maturityTime, 1, expiry, signature), 1);
        vm.expectRevert(bytes("APPROVAL_EXPIRED_OR_USED"));
        registry.publish(r, maturityTime, 1, expiry, signature);
    }

    function testTradingContinuesAfterVotingCloses() public {
        uint256 id = publish(report(), maturityTime, 1);
        vault.initializeSeries(id);
        vm.prank(ALICE);
        vault.stake(id, true, 50_000_000, ALICE, ALICE);
        vm.prank(BOB);
        vault.stake(id, false, 50_000_000, BOB, BOB);

        PoolManager manager = new PoolManager(address(this));
        YieldCurveHookV2 implementation = new YieldCurveHookV2(
            IPoolManager(address(manager)), usd, vault.yt(), maturityTime, 3000, 1e17, 5e6, 5e16, 2e17
        );
        address hookAddress = address(uint160(implementation.REQUIRED_FLAGS()));
        vm.etch(hookAddress, address(implementation).code);
        YieldCurveHookV2 hook = YieldCurveHookV2(hookAddress);
        address c0 = address(usd) < address(vault.yt()) ? address(usd) : address(vault.yt());
        address c1 = address(usd) < address(vault.yt()) ? address(vault.yt()) : address(usd);
        PoolKey memory key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 0, 1, IHooks(hookAddress));
        hook.configurePool(key);
        manager.initialize(key, 1 << 96);
        YieldSwapRouter router = new YieldSwapRouter(IPoolManager(address(manager)));
        vm.startPrank(BOB);
        usd.approve(address(hook), type(uint256).max);
        vault.yt().approve(address(hook), type(uint256).max);
        hook.addLiquidity(10_000_000, 20_000_000, 1);
        vm.stopPrank();

        vm.warp(lockTime + 1);
        vm.startPrank(ALICE);
        vault.yt().approve(address(router), type(uint256).max);
        vm.stopPrank();
        uint256 quote = hook.quoteSell(10_000_000);
        bool ytIsCurrency0 = address(vault.yt()) < address(usd);
        vm.prank(ALICE);
        uint256 received =
            router.swapExactInput(key, ytIsCurrency0, 10_000_000, quote, uint64(block.timestamp + 5 minutes));
        assertEq(received, quote);
        assertEq(vault.yt().balanceOf(ALICE), 40_000_000);

        vm.warp(maturityTime);
        vm.expectRevert();
        hook.quoteSell(10_000_000);
    }
}
