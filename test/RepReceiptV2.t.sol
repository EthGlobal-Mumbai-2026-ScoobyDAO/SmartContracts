// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "./Voting.t.sol";
import {ReportRegistry} from "../src/ReportRegistry.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";
import {StakerYieldToken} from "../src/v2/StakerYieldToken.sol";
import {StakeReceiptREP} from "../src/v2/StakeReceiptREP.sol";

/// @notice REP receipt: 1 collateral -> 1 REP; staking burns REP and mints position + YT;
/// unstaked REP is always withdrawable 1:1 and never exposed to loss, settlement or sweeps.
contract RepReceiptV2Test is Test {
    uint256 constant REVIEWER_KEY = 0xA11CE;
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant CAROL = address(0xCA401);
    address constant TREASURY = address(0x7EA5);
    MockUSDC usdc;
    ReportRegistry registry;
    RiskFiStakeVaultV2 vault;
    StakeReceiptREP rep;
    StakerYieldToken yt;
    uint256 reportId;
    uint64 lockTime;

    function setUp() public {
        usdc = new MockUSDC();
        registry = new ReportRegistry(address(this));
        vault = new RiskFiStakeVaultV2(usdc, registry, address(this), TREASURY);
        rep = vault.rep();
        lockTime = uint64(block.timestamp + 2 days);
        ReportRegistry.Report memory r = ReportRegistry.Report({
            reportHash: keccak256("rep report"),
            claimHash: keccak256("rep claim"),
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
        _fund(ALICE, 100_000_000);
        _fund(BOB, 100_000_000);
        _fund(CAROL, 100_000_000);
    }

    function _fund(address who, uint256 amount) internal {
        usdc.mint(who, amount);
        vm.prank(who);
        usdc.approve(address(vault), type(uint256).max);
    }

    function testDepositMintsREPAndStakingBurnsItOnce() public {
        vm.startPrank(ALICE);
        vault.deposit(100_000_000, ALICE);
        assertEq(rep.balanceOf(ALICE), 100_000_000, "1 collateral -> 1 REP");
        assertEq(usdc.balanceOf(address(vault)), 100_000_000);

        vault.stakeFromREP(reportId, true, 60_000_000, ALICE, ALICE);
        assertEq(rep.balanceOf(ALICE), 40_000_000, "staked REP is burned");
        assertEq(vault.positionOf(ALICE, true), 60_000_000, "1 REP -> 1 PT notional");
        assertEq(yt.balanceOf(ALICE), 60_000_000, "1 REP -> 1 YT");

        vm.expectRevert(bytes("REP_BALANCE"));
        vault.stakeFromREP(reportId, true, 50_000_000, ALICE, ALICE); // cannot stake the same REP twice

        vault.withdraw(40_000_000);
        vm.stopPrank();
        assertEq(rep.totalSupply(), 0);
        assertEq(usdc.balanceOf(ALICE), 40_000_000);
        assertEq(usdc.balanceOf(address(vault)), 60_000_000, "only staked principal remains");
    }

    function testDirectStakePassesThroughREPAndLeavesNone() public {
        vm.prank(ALICE);
        vault.stake(reportId, true, 30_000_000, ALICE, ALICE);
        assertEq(rep.totalSupply(), 0, "deposit->burn inside stake");
        assertEq(vault.positionOf(ALICE, true), 30_000_000);
        assertEq(yt.balanceOf(ALICE), 30_000_000);
    }

    function testDepositForAnotherOwnerAndTransferREP() public {
        vm.prank(ALICE);
        vault.deposit(10_000_000, BOB); // Alice pays, Bob owns the REP
        assertEq(rep.balanceOf(BOB), 10_000_000);
        vm.prank(BOB);
        rep.transfer(CAROL, 4_000_000);
        vm.prank(CAROL);
        vault.stakeFromREP(reportId, false, 4_000_000, CAROL, CAROL);
        assertEq(vault.positionOf(CAROL, false), 4_000_000);
        vm.prank(BOB);
        vm.expectRevert(bytes("REP_BALANCE"));
        vault.withdraw(7_000_000);
        vm.prank(BOB);
        vault.withdraw(6_000_000);
        assertEq(usdc.balanceOf(BOB), 106_000_000);
    }

    function testStakingClosesAtLockButREPStaysWithdrawable() public {
        vm.prank(ALICE);
        vault.deposit(5_000_000, ALICE);
        vm.warp(lockTime);
        vm.prank(ALICE);
        vm.expectRevert(bytes("CLOSED"));
        vault.stakeFromREP(reportId, true, 5_000_000, ALICE, ALICE);
        vm.prank(ALICE);
        vault.deposit(1_000_000, ALICE); // deposits are not gated by the lock
        vm.prank(ALICE);
        vault.withdraw(6_000_000);
        assertEq(usdc.balanceOf(ALICE), 100_000_000);
    }

    /// Idle REP collateral sits in the same contract as staked principal. It must not absorb a
    /// simulated loss, inflate principalAvailable at settlement, or be swept as dust.
    function testIdleREPRingFencedFromLossSettlementAndSweep() public {
        vm.prank(ALICE);
        vault.stake(reportId, true, 80_000_000, ALICE, ALICE);
        vm.prank(BOB);
        vault.stake(reportId, false, 20_000_000, BOB, BOB);
        vm.prank(CAROL);
        vault.deposit(50_000_000, CAROL); // idle REP, never staked
        assertEq(usdc.balanceOf(address(vault)), 150_000_000);

        vm.expectRevert(bytes("LOSS_EXCEEDS_STAKE"));
        vault.simulateLoss(address(0xDEAD), 100_000_001);
        vault.simulateLoss(address(0xDEAD), 10_000_000); // 10% of staked principal

        vm.warp(uint256(lockTime) + 30 days);
        vault.propose(RiskFiStakeVaultV2.Outcome.Yes, keccak256("evidence"));
        vm.warp(block.timestamp + 1 days);
        vault.finalize();
        assertEq(vault.principalAvailable(), 90_000_000, "REP collateral not counted as principal");

        vm.prank(ALICE);
        assertEq(vault.claimPrincipal(true, 80_000_000), 86_400_000, "96 nominal x 90%");
        assertEq(vault.claimFee(), 3_600_000, "4 nominal x 90%");

        vm.warp(uint256(vault.finalizedAt()) + 90 days + 1);
        vault.sweepDust();
        assertEq(usdc.balanceOf(address(vault)), 50_000_000, "sweep leaves REP collateral");
        vm.prank(CAROL);
        vault.withdraw(50_000_000);
        assertEq(usdc.balanceOf(CAROL), 100_000_000, "idle REP fully returned after a loss");
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function testOnlyVaultMintsOrBurnsREP() public {
        vm.expectRevert(bytes("MINT"));
        rep.mint(ALICE, 1);
        vm.prank(ALICE);
        vault.deposit(1_000_000, ALICE);
        vm.expectRevert(bytes("BURN"));
        rep.burn(ALICE, 1);
    }
}
