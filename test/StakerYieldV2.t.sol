// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "./Voting.t.sol";
import {ReportRegistry} from "../src/ReportRegistry.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";
import {StakerYieldToken} from "../src/v2/StakerYieldToken.sol";

contract StakerYieldV2Test is Test {
    uint256 constant REVIEWER_KEY = 0xA11CE;
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant TREASURY = address(0x7EA5);
    MockUSDC usdc;
    ReportRegistry registry;
    RiskFiStakeVaultV2 vault;
    StakerYieldToken yt;
    uint256 reportId;
    uint64 lockTime;

    function setUp() public {
        usdc = new MockUSDC();
        registry = new ReportRegistry(address(this));
        vault = new RiskFiStakeVaultV2(usdc, registry, address(this), TREASURY);
        lockTime = uint64(block.timestamp + 2 days);
        ReportRegistry.Report memory r = ReportRegistry.Report({
            reportHash: keccak256("v2 report"),
            claimHash: keccak256("v2 claim"),
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
        reportId = registry.publish(r, 1, expiry, abi.encodePacked(a, b, v));
        vault.initializeSeries(reportId);
        yt = vault.yt();
        usdc.mint(ALICE, 80_000_000);
        usdc.mint(BOB, 20_000_000);
        usdc.mint(address(this), 25_000_000);
        vm.prank(ALICE);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(BOB);
        usdc.approve(address(vault), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
    }

    function testStakerOwnsYTAndOnlyFutureYieldTransfers() public {
        vm.prank(ALICE);
        vault.stake(reportId, true, 80_000_000, ALICE, ALICE);
        assertEq(yt.balanceOf(ALICE), 80_000_000);
        vault.injectYield(8_000_000);
        vm.prank(ALICE);
        yt.transfer(BOB, 40_000_000);
        vm.prank(BOB);
        vault.stake(reportId, false, 20_000_000, BOB, BOB);
        vault.injectYield(15_000_000);
        vm.prank(ALICE);
        assertEq(yt.claimYield(), 14_000_000);
        vm.prank(BOB);
        assertEq(yt.claimYield(), 9_000_000);
        assertEq(usdc.balanceOf(address(yt)), 0);
        vm.warp(lockTime + 30 days);
        vault.propose(RiskFiStakeVaultV2.Outcome.Yes, keccak256("evidence"));
        vm.warp(block.timestamp + 1 days);
        vault.finalize();
        vm.prank(ALICE);
        assertEq(vault.claimPrincipal(true, 80_000_000), 96_000_000);
        vm.prank(BOB);
        assertEq(vault.claimPrincipal(false, 20_000_000), 0);
        assertEq(vault.claimFee(), 4_000_000);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function testLateMintCannotTakeEarlierYieldAndVoidRefunds() public {
        vm.prank(ALICE);
        vault.stake(reportId, true, 80_000_000, ALICE, ALICE);
        vault.injectYield(8_000_000);
        vm.prank(BOB);
        vault.stake(reportId, false, 20_000_000, BOB, BOB);
        vm.prank(BOB);
        assertEq(yt.claimYield(), 0);
        vm.prank(ALICE);
        assertEq(yt.claimYield(), 8_000_000);
        vm.warp(lockTime + 30 days);
        vault.propose(RiskFiStakeVaultV2.Outcome.Void, keccak256("invalid"));
        vm.warp(block.timestamp + 1 days);
        vault.finalize();
        vm.prank(ALICE);
        assertEq(vault.claimPrincipal(true, 80_000_000), 80_000_000);
        vm.prank(BOB);
        assertEq(vault.claimPrincipal(false, 20_000_000), 20_000_000);
        vm.expectRevert();
        vm.prank(ALICE);
        vault.claimPrincipal(true, 1);
    }

    function testPrincipalLossAndChallengedAdjudication() public {
        vm.prank(ALICE);
        vault.stake(reportId, true, 80_000_000, ALICE, ALICE);
        vm.prank(BOB);
        vault.stake(reportId, false, 20_000_000, BOB, BOB);
        vault.simulateLoss(address(0xDEAD), 10_000_000);
        vm.warp(lockTime + 30 days);
        vault.propose(RiskFiStakeVaultV2.Outcome.No, keccak256("initial evidence"));
        vault.challenge(keccak256("counterevidence"));
        vm.expectRevert();
        vault.finalize();
        vault.adjudicate(RiskFiStakeVaultV2.Outcome.Yes, keccak256("reviewed evidence"));
        vm.prank(ALICE);
        assertEq(vault.claimPrincipal(true, 80_000_000), 86_400_000);
        assertEq(vault.claimFee(), 3_600_000);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }
}
