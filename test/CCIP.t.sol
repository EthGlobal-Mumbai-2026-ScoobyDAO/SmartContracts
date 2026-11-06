// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Vm, MockUSDC} from "./Voting.t.sol";
import {Client} from "chainlink-ccip/libraries/Client.sol";
import {IRouterClient} from "chainlink-ccip/interfaces/IRouterClient.sol";
import {IAny2EVMMessageReceiver} from "chainlink-ccip/interfaces/IAny2EVMMessageReceiver.sol";
import {ReportRegistry} from "../src/ReportRegistry.sol";
import {VotingPositionToken} from "../src/VotingPositionToken.sol";
import {VoteMarket} from "../src/VoteMarket.sol";
import {Settlement} from "../src/Settlement.sol";
import {Reputation} from "../src/Reputation.sol";
import {YieldSplitter} from "../src/yield/YieldSplitter.sol";
import {YieldVaultAdapter} from "../src/yield/YieldVaultAdapter.sol";
import {YieldToken} from "../src/yield/YieldToken.sol";
import {CCIPStakeSender} from "../src/ccip/CCIPStakeSender.sol";
import {CCIPStakeReceiver} from "../src/ccip/CCIPStakeReceiver.sol";
import {StakeIntent} from "../src/ccip/StakeIntent.sol";

contract MockCCIPRouter is IRouterClient {
    uint64 public constant SOURCE = 12345;
    uint256 public sequence;
    bool public duplicate;
    bool public autoDeliver = true;
    mapping(bytes32 => bytes) public pending;

    function setAutoDeliver(bool enabled) external {
        autoDeliver = enabled;
    }

    function isChainSupported(uint64) external pure returns (bool) {
        return true;
    }

    function getFee(uint64, Client.EVM2AnyMessage memory) external pure returns (uint256) {
        return 0;
    }

    function ccipSend(uint64, Client.EVM2AnyMessage calldata message) external payable returns (bytes32 messageId) {
        messageId = keccak256(abi.encode(++sequence, msg.sender));
        address receiver = abi.decode(message.receiver, (address));
        Client.EVMTokenAmount[] memory tokens = new Client.EVMTokenAmount[](message.tokenAmounts.length);
        for (uint256 i; i < tokens.length; i++) {
            tokens[i] = message.tokenAmounts[i];
            require(MockUSDC(tokens[i].token).transferFrom(msg.sender, address(this), tokens[i].amount), "transfer");
        }
        Client.Any2EVMMessage memory delivered =
            Client.Any2EVMMessage(messageId, SOURCE, abi.encode(msg.sender), message.data, tokens);
        pending[messageId] = abi.encode(receiver, delivered);
        if (autoDeliver) deliver(messageId);
    }

    function deliver(bytes32 messageId) public {
        bytes memory payload = pending[messageId];
        require(payload.length != 0, "PENDING");
        delete pending[messageId];
        (address receiver, Client.Any2EVMMessage memory delivered) =
            abi.decode(payload, (address, Client.Any2EVMMessage));
        for (uint256 i; i < delivered.destTokenAmounts.length; i++) {
            Client.EVMTokenAmount memory token = delivered.destTokenAmounts[i];
            require(MockUSDC(token.token).transfer(receiver, token.amount), "transfer");
        }
        IAny2EVMMessageReceiver(receiver).ccipReceive(delivered);
        if (duplicate) IAny2EVMMessageReceiver(receiver).ccipReceive(delivered);
    }
}

contract CCIPTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant REVIEWER_KEY = 0xA11CE;
    address internal constant ALICE = address(0xA11CE);
    MockUSDC usdc;
    MockCCIPRouter router;
    ReportRegistry registry;
    VotingPositionToken positions;
    VoteMarket market;
    Settlement settlement;
    CCIPStakeSender sender;
    CCIPStakeReceiver receiver;
    uint256 id;
    uint256 lockTime;

    function setUp() public {
        usdc = new MockUSDC();
        router = new MockCCIPRouter();
        registry = new ReportRegistry(address(this));
        positions = new VotingPositionToken();
        market = new VoteMarket(usdc, registry, positions);
        settlement = new Settlement(registry, market, positions, address(0x7EA5));
        receiver =
            new CCIPStakeReceiver(address(router), router.SOURCE(), address(0), usdc, market, registry, address(this));
        sender = new CCIPStakeSender(router, usdc, 98765, address(receiver));
        receiver.configureSourceSender(address(sender));
        positions.configure(address(market), address(settlement));
        market.configure(address(settlement), address(receiver));
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
        sender.configureReportCutoff(id, uint64(lockTime - 1 days));
        usdc.mint(ALICE, 10_000_000);
        vm.prank(ALICE);
        usdc.approve(address(sender), type(uint256).max);
    }

    function _intent(uint256 nonce) internal view returns (StakeIntent memory) {
        return StakeIntent(1, id, true, ALICE, nonce, uint64(lockTime + 1 days), 1_000_000);
    }

    function testOfficialClientMessageCreditsFundedStake() public {
        vm.prank(ALICE);
        sender.stakeRemote(_intent(1), 5_000_000, "");
        require(market.total(id, true) == 5_000_000, "credit");
        require(positions.balanceOf(ALICE, positions.tokenId(id, true)) == 5_000_000, "VPT");
        require(usdc.balanceOf(address(market)) == 5_000_000, "funded");
        vm.expectRevert();
        vm.prank(ALICE);
        sender.stakeRemote(_intent(1), 5_000_000, "");
    }

    function testLateDeliveryRecoverable() public {
        router.setAutoDeliver(false);
        vm.prank(ALICE);
        sender.stakeRemote(_intent(2), 5_000_000, "");
        vm.warp(lockTime);
        bytes32 messageId = keccak256(abi.encode(uint256(1), address(sender)));
        router.deliver(messageId);
        require(receiver.recoverable(messageId) == 5_000_000, "held");
        require(market.total(id, true) == 0, "no vote");
        vm.prank(ALICE);
        receiver.recover(messageId, ALICE);
        require(usdc.balanceOf(ALICE) == 10_000_000, "refund");
    }

    function testEightVoterCCIPYieldSettlementAndREPWorkflow() public {
        YieldSplitter splitter =
            new YieldSplitter(usdc, registry, address(market), address(settlement), address(0x7EA5));
        YieldVaultAdapter vault = new YieldVaultAdapter(usdc, address(splitter), address(this));
        splitter.configureVault(vault);
        market.configureSplitter(splitter);

        // Alice funds the Yes side through the official Client message shape.
        vm.prank(ALICE);
        sender.stakeRemote(_intent(3), 5_000_000, "");
        require(positions.balanceOf(ALICE, positions.tokenId(id, true)) == 5_000_000, "remote receipt");
        for (uint256 i; i < 7; i++) {
            address voter = address(uint160(0x100 + i));
            usdc.mint(voter, 10_000_000);
            vm.prank(voter);
            usdc.approve(address(market), 10_000_000);
            vm.prank(voter);
            market.stakeLocal(id, i < 4, 10_000_000, voter);
        }
        require(market.total(id, true) == 45_000_000, "five yes voters");
        require(market.total(id, false) == 30_000_000, "three no voters");
        require(usdc.balanceOf(address(market)) == 75_000_000, "all votes funded");

        vm.warp(lockTime);
        market.lock(id);
        YieldToken yt = splitter.yieldToken(id);
        require(splitter.principalToken().balanceOf(id, address(settlement)) == 75_000_000, "PT escrow");
        require(yt.balanceOf(address(0x7EA5)) == 75_000_000, "YT treasury");
        usdc.mint(address(this), 7_500_000);
        usdc.approve(address(vault), 7_500_000);
        vault.injectYield(7_500_000);
        splitter.checkpointYield(id);
        vm.prank(address(0x7EA5));
        require(yt.claimYield() == 7_500_000, "YT yield separate from verdict");

        vm.warp(lockTime + 30 days);
        settlement.propose(id, Settlement.Outcome.Yes, keccak256("evidence"));
        vm.warp(block.timestamp + 1 days);
        settlement.finalize(id);
        uint256 winnerPaid;
        vm.prank(ALICE);
        winnerPaid += settlement.redeemVPT(id, true, 5_000_000);
        for (uint256 i; i < 7; i++) {
            address voter = address(uint160(0x100 + i));
            vm.prank(voter);
            uint256 paid = settlement.redeemVPT(id, i < 4, 10_000_000);
            if (i < 4) winnerPaid += paid;
            else require(paid == 0, "loser paid");
        }
        settlement.claimFee(id);
        require(usdc.balanceOf(address(0x7EA5)) == 13_500_000, "yield plus six fee");
        require(winnerPaid + 6_000_000 <= 75_000_000, "principal solvent");
        require(75_000_000 - winnerPaid - 6_000_000 <= 5, "bounded principal dust");

        Reputation reputation = new Reputation(settlement, vm.addr(REVIEWER_KEY));
        bytes32 nullifier = keccak256("scoped-human-claim");
        uint64 expiry = uint64(block.timestamp + 1 hours);
        bytes32 digest = reputation.authorizationDigest(id, ALICE, nullifier, 7, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(REVIEWER_KEY, digest);
        reputation.claimWinnerREP(id, ALICE, nullifier, 7, expiry, abi.encodePacked(r, s, v));
        require(reputation.balanceOf(ALICE, id) == 1, "winning human badge");
        vm.expectRevert();
        reputation.claimWinnerREP(id, ALICE, nullifier, 7, expiry, abi.encodePacked(r, s, v));

        vm.warp(block.timestamp + 90 days + 1);
        settlement.sweepDust(id);
        require(usdc.balanceOf(address(market)) == 0, "all principal accounted");
    }
}
