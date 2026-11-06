// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Vm, MockUSDC} from "./Voting.t.sol";
import {ReportRegistry} from "../src/ReportRegistry.sol";
import {VotingPositionToken} from "../src/VotingPositionToken.sol";
import {VoteMarket} from "../src/VoteMarket.sol";
import {Settlement} from "../src/Settlement.sol";
import {YieldSplitter} from "../src/yield/YieldSplitter.sol";
import {YieldVaultAdapter} from "../src/yield/YieldVaultAdapter.sol";
import {YieldToken} from "../src/yield/YieldToken.sol";

contract YieldAccountingTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant TREASURY = address(0x7EA5);
    uint256 internal constant REVIEWER_KEY = 0xA11CE;
    MockUSDC usdc;
    ReportRegistry registry;
    VotingPositionToken positions;
    VoteMarket market;
    Settlement settlement;
    YieldSplitter splitter;
    YieldVaultAdapter vault;
    uint256 id;
    uint256 lockTime;

    function setUp() public {
        usdc = new MockUSDC();
        registry = new ReportRegistry(address(this));
        positions = new VotingPositionToken();
        market = new VoteMarket(usdc, registry, positions);
        settlement = new Settlement(registry, market, positions, TREASURY);
        splitter = new YieldSplitter(usdc, registry, address(market), address(settlement), TREASURY);
        vault = new YieldVaultAdapter(usdc, address(splitter), address(this));
        splitter.configureVault(vault);
        positions.configure(address(market), address(settlement));
        market.configure(address(settlement), address(0xCC1));
        market.configureSplitter(splitter);
        lockTime = block.timestamp + 2 days;
        ReportRegistry.Report memory r = ReportRegistry.Report({
            reportHash: keccak256("report"),
            claimHash: keccak256("claim"),
            reviewer: vm.addr(REVIEWER_KEY),
            resolver: address(this),
            adjudicator: address(this),
            lockTime: uint64(lockTime),
            crossChainCutoff: uint64(lockTime - 1 days),
            resultDeadline: uint64(lockTime + 33 days),
            challengePeriod: 1 days
        });
        uint64 expiry = uint64(block.timestamp + 1 days);
        (uint8 v, bytes32 a, bytes32 b) = vm.sign(REVIEWER_KEY, registry.approvalDigest(r, 1, expiry));
        id = registry.publish(r, 1, expiry, abi.encodePacked(a, b, v));
        usdc.mint(ALICE, 80_000_000);
        usdc.mint(BOB, 20_000_000);
        usdc.mint(address(this), 25_000_000);
        vm.prank(ALICE);
        usdc.approve(address(market), type(uint256).max);
        vm.prank(BOB);
        usdc.approve(address(market), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
    }

    function testYieldFollowsHolderThenPrincipalSettles() public {
        vm.prank(ALICE);
        market.stakeLocal(id, true, 80_000_000, ALICE);
        vm.prank(BOB);
        market.stakeLocal(id, false, 20_000_000, BOB);
        vm.warp(lockTime);
        market.lock(id);
        YieldToken yt = splitter.yieldToken(id);
        require(splitter.principalToken().balanceOf(id, address(settlement)) == 100_000_000, "PT escrow");
        require(yt.balanceOf(TREASURY) == 100_000_000, "YT issuance");
        vault.injectYield(10_000_000);
        splitter.checkpointYield(id);
        vm.prank(TREASURY);
        yt.transfer(ALICE, 50_000_000);
        vault.injectYield(15_000_000);
        splitter.checkpointYield(id);
        vm.prank(TREASURY);
        require(yt.claimYield() == 17_500_000, "treasury yield");
        vm.prank(ALICE);
        require(yt.claimYield() == 7_500_000, "Alice yield");
        require(usdc.balanceOf(address(yt)) == 0, "yield conservation");
        vm.warp(lockTime + 30 days);
        settlement.propose(id, Settlement.Outcome.Yes, keccak256("evidence"));
        vm.warp(block.timestamp + 1 days);
        settlement.finalize(id);
        vm.prank(ALICE);
        settlement.redeemVPT(id, true, 80_000_000);
        settlement.claimFee(id);
        require(usdc.balanceOf(ALICE) == 103_500_000, "principal plus yield");
        require(usdc.balanceOf(address(market)) == 0, "principal conservation");
    }

    function testPrincipalShortfallProRata() public {
        vm.prank(ALICE);
        market.stakeLocal(id, true, 80_000_000, ALICE);
        vm.prank(BOB);
        market.stakeLocal(id, false, 20_000_000, BOB);
        vm.warp(lockTime);
        market.lock(id);
        vault.simulateLoss(address(0xDEAD), 10_000_000);
        vm.warp(lockTime + 30 days);
        settlement.propose(id, Settlement.Outcome.Yes, keccak256("evidence"));
        vm.warp(block.timestamp + 1 days);
        settlement.finalize(id);
        vm.prank(ALICE);
        require(settlement.redeemVPT(id, true, 80_000_000) == 86_400_000, "scaled payout");
        settlement.claimFee(id);
        require(usdc.balanceOf(address(market)) == 0, "shortfall conservation");
    }
}
