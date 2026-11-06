// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "./Voting.t.sol";
import {MockCCIPRouter} from "./CCIP.t.sol";
import {Client} from "chainlink-ccip/libraries/Client.sol";
import {ReportRegistry} from "../src/ReportRegistry.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";
import {StakerYieldToken} from "../src/v2/StakerYieldToken.sol";
import {CCIPStakeSenderV2} from "../src/v2/CCIPStakeSenderV2.sol";
import {CCIPStakeReceiverV2} from "../src/v2/CCIPStakeReceiverV2.sol";
import {StakeIntentV2} from "../src/v2/StakeIntentV2.sol";

contract CCIPV2Test is Test {
    uint256 constant REVIEWER_KEY = 0xA11CE;
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant CAROL = address(0xCA401);
    address constant TREASURY = address(0x7EA5);
    MockUSDC usdc;
    MockCCIPRouter router;
    ReportRegistry registry;
    RiskFiStakeVaultV2 vault;
    CCIPStakeSenderV2 sender;
    CCIPStakeReceiverV2 receiver;
    StakerYieldToken yt;
    uint256 reportId;
    uint64 lockTime;

    function setUp() public {
        usdc = new MockUSDC();
        router = new MockCCIPRouter();
        registry = new ReportRegistry(address(this));
        vault = new RiskFiStakeVaultV2(usdc, registry, address(this), TREASURY);
        lockTime = uint64(block.timestamp + 2 days);
        ReportRegistry.Report memory report = ReportRegistry.Report({
            reportHash: keccak256("v2 ccip report"),
            claimHash: keccak256("v2 ccip claim"),
            reviewer: vm.addr(REVIEWER_KEY),
            resolver: address(this),
            adjudicator: address(this),
            lockTime: lockTime,
            crossChainCutoff: uint64(lockTime - 1 days),
            resultDeadline: uint64(uint256(lockTime) + 33 days),
            challengePeriod: 1 days
        });
        uint64 expiry = uint64(block.timestamp + 1 days);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(REVIEWER_KEY, registry.approvalDigest(report, 1, expiry));
        reportId = registry.publish(report, 1, expiry, abi.encodePacked(r, s, v));
        vault.initializeSeries(reportId);
        yt = vault.yt();
        receiver = new CCIPStakeReceiverV2(address(router), router.SOURCE(), usdc, vault, address(this));
        sender = new CCIPStakeSenderV2(router, usdc, 98765, address(receiver));
        receiver.configureSourceSender(address(sender));
        sender.configureReportCutoff(reportId, uint64(lockTime - 1 days));
        usdc.mint(ALICE, 10_000_000);
        usdc.mint(BOB, 10_000_000);
        vm.prank(ALICE);
        usdc.approve(address(sender), type(uint256).max);
        vm.prank(BOB);
        usdc.approve(address(sender), type(uint256).max);
    }

    function _intent(address sourceAccount, address recipient, uint256 nonce)
        internal
        view
        returns (StakeIntentV2 memory)
    {
        return StakeIntentV2(2, reportId, true, sourceAccount, recipient, nonce, uint64(lockTime + 1 days), 1_000_000);
    }

    function testTwoPayersMayReuseNonceAndFundIndependentV2Positions() public {
        vm.prank(ALICE);
        sender.stakeRemote(_intent(ALICE, CAROL, 7), 3_000_000, "");
        vm.prank(BOB);
        sender.stakeRemote(_intent(BOB, BOB, 7), 4_000_000, "");
        assertEq(vault.positionOf(CAROL, true), 3_000_000);
        assertEq(vault.positionOf(BOB, true), 4_000_000);
        assertEq(yt.balanceOf(CAROL), 3_000_000);
        assertEq(yt.balanceOf(BOB), 4_000_000);
        assertEq(usdc.balanceOf(address(vault)), 7_000_000);
        vm.expectRevert();
        vm.prank(ALICE);
        sender.stakeRemote(_intent(ALICE, CAROL, 7), 1_000_000, "");
        vm.expectRevert();
        vm.prank(ALICE);
        sender.stakeRemote(_intent(BOB, BOB, 8), 1_000_000, "");
    }

    function testLateDeliveryReturnsCollateralToSourcePayer() public {
        router.setAutoDeliver(false);
        vm.prank(ALICE);
        sender.stakeRemote(_intent(ALICE, BOB, 2), 5_000_000, "");
        bytes32 messageId = keccak256(abi.encode(uint256(1), address(sender)));
        vm.warp(lockTime);
        router.deliver(messageId);
        // Late delivery: collateral is credited as REP to the source payer, not staked.
        assertEq(receiver.recoverable(messageId), 0, "no raw refund balance");
        assertEq(vault.rep().balanceOf(ALICE), 5_000_000, "payer holds REP");
        assertEq(vault.rep().balanceOf(address(receiver)), 0);
        assertEq(vault.rep().balanceOf(BOB), 0, "recipient gets nothing for a failed stake");
        assertEq(vault.positionOf(BOB, true), 0);
        assertEq(yt.balanceOf(BOB), 0);
        assertEq(usdc.balanceOf(address(receiver)), 0);
        assertEq(usdc.balanceOf(address(vault)), 5_000_000, "REP collateral held by the vault");
        vm.expectRevert(bytes("NO_FUNDS"));
        vm.prank(ALICE);
        receiver.recover(messageId, ALICE);
        // REP after lock cannot be staked, but it can always be withdrawn 1:1.
        vm.expectRevert(bytes("CLOSED"));
        vm.prank(ALICE);
        vault.stakeFromREP(reportId, true, 5_000_000, ALICE, ALICE);
        vm.prank(ALICE);
        vault.withdraw(5_000_000);
        assertEq(usdc.balanceOf(ALICE), 10_000_000);
        assertEq(vault.rep().totalSupply(), 0);
    }

    function testExpiredDeadlineBeforeLockAlsoBecomesREPThatCanBeStaked() public {
        router.setAutoDeliver(false);
        StakeIntentV2 memory intent = _intent(ALICE, BOB, 3);
        intent.deadline = uint64(block.timestamp + 1 hours);
        vm.prank(ALICE);
        sender.stakeRemote(intent, 2_000_000, "");
        bytes32 messageId = keccak256(abi.encode(uint256(1), address(sender)));
        vm.warp(block.timestamp + 2 hours); // past the intent deadline, still before lock
        router.deliver(messageId);
        assertEq(vault.rep().balanceOf(ALICE), 2_000_000);
        assertEq(vault.positionOf(BOB, true), 0);
        // The payer chooses to stake the REP herself on this chain.
        vm.prank(ALICE);
        vault.stakeFromREP(reportId, false, 2_000_000, ALICE, ALICE);
        assertEq(vault.positionOf(ALICE, false), 2_000_000);
        assertEq(yt.balanceOf(ALICE), 2_000_000);
        assertEq(vault.rep().totalSupply(), 0);
    }

    function testMalformedDeliveryNeedsRecoveryOperatorAndWrongChainReverts() public {
        Client.EVMTokenAmount[] memory tokens = new Client.EVMTokenAmount[](1);
        tokens[0] = Client.EVMTokenAmount(address(usdc), 1_000_000);
        usdc.mint(address(receiver), 1_000_000);
        Client.Any2EVMMessage memory wrongChain =
            Client.Any2EVMMessage(keccak256("wrong chain"), 999, abi.encode(address(sender)), "broken", tokens);
        vm.expectRevert();
        vm.prank(address(router));
        receiver.ccipReceive(wrongChain);
        Client.Any2EVMMessage memory malformed = Client.Any2EVMMessage(
            keccak256("malformed"), router.SOURCE(), abi.encode(address(sender)), "broken", tokens
        );
        vm.prank(address(router));
        receiver.ccipReceive(malformed);
        assertEq(receiver.recoverable(malformed.messageId), 1_000_000);
        vm.expectRevert();
        vm.prank(ALICE);
        receiver.recover(malformed.messageId, ALICE);
        receiver.recover(malformed.messageId, TREASURY);
        assertEq(usdc.balanceOf(TREASURY), 1_000_000);
    }

    function testOnlyRouterMayDeliverAndMessageCannotReplay() public {
        vm.prank(ALICE);
        sender.stakeRemote(_intent(ALICE, ALICE, 11), 1_000_000, "");
        bytes32 messageId = keccak256(abi.encode(uint256(1), address(sender)));
        Client.EVMTokenAmount[] memory tokens = new Client.EVMTokenAmount[](1);
        tokens[0] = Client.EVMTokenAmount(address(usdc), 1_000_000);
        Client.Any2EVMMessage memory replay = Client.Any2EVMMessage(
            messageId, router.SOURCE(), abi.encode(address(sender)), abi.encode(_intent(ALICE, ALICE, 11)), tokens
        );
        vm.expectRevert();
        receiver.ccipReceive(replay);
        vm.expectRevert(bytes("REPLAY"));
        vm.prank(address(router));
        receiver.ccipReceive(replay);
        assertEq(vault.positionOf(ALICE, true), 1_000_000);
    }
}
