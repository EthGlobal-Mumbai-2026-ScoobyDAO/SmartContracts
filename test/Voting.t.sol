// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IERC20} from "../src/Utils.sol";
import {ReportRegistry} from "../src/ReportRegistry.sol";
import {VotingPositionToken} from "../src/VotingPositionToken.sol";
import {VoteMarket} from "../src/VoteMarket.sol";
import {Settlement} from "../src/Settlement.sol";
import {Reputation} from "../src/Reputation.sol";

interface Vm {
    function warp(uint256) external;
    function prank(address) external;
    function sign(uint256, bytes32) external returns (uint8, bytes32, bytes32);
    function addr(uint256) external returns (address);
    function expectRevert() external;
}

contract MockUSDC is IERC20 {
    string public constant name = "Mock USDC";
    string public constant symbol = "mUSDC";
    uint8 public constant decimals = 6;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract VotingTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant REVIEWER_KEY = 0xA11CE;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA401);
    address internal constant TREASURY = address(0x7EA5);
    MockUSDC usdc;
    ReportRegistry registry;
    VotingPositionToken positions;
    VoteMarket market;
    Settlement settlement;
    Reputation reputation;
    uint256 id;
    uint256 lockTime;

    function setUp() public {
        usdc = new MockUSDC();
        registry = new ReportRegistry(address(this));
        positions = new VotingPositionToken();
        market = new VoteMarket(usdc, registry, positions);
        settlement = new Settlement(registry, market, positions, TREASURY);
        reputation = new Reputation(settlement, vm.addr(REVIEWER_KEY));
        positions.configure(address(market), address(settlement));
        market.configure(address(settlement), address(0xCC1));
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
        bytes32 digest = registry.approvalDigest(r, 1, expiry);
        (uint8 v, bytes32 s1, bytes32 s2) = vm.sign(REVIEWER_KEY, digest);
        id = registry.publish(r, 1, expiry, abi.encodePacked(s1, s2, v));
        usdc.mint(ALICE, 80_000_000);
        usdc.mint(BOB, 20_000_000);
        vm.prank(ALICE);
        usdc.approve(address(market), type(uint256).max);
        vm.prank(BOB);
        usdc.approve(address(market), type(uint256).max);
    }

    function _stake(bool aliceYes) internal {
        vm.prank(ALICE);
        market.stakeLocal(id, aliceYes, 80_000_000, ALICE);
        vm.prank(BOB);
        market.stakeLocal(id, !aliceYes, 20_000_000, BOB);
    }

    function _finalize(Settlement.Outcome outcome) internal {
        vm.warp(lockTime + 30 days);
        settlement.propose(id, outcome, keccak256("evidence"));
        vm.warp(block.timestamp + 1 days);
        settlement.finalize(id);
    }

    function testYes80No20() public {
        _stake(true);
        _finalize(Settlement.Outcome.Yes);
        vm.prank(ALICE);
        settlement.redeemVPT(id, true, 80_000_000);
        vm.prank(BOB);
        settlement.redeemVPT(id, false, 20_000_000);
        settlement.claimFee(id);
        require(usdc.balanceOf(ALICE) == 96_000_000, "winner");
        require(usdc.balanceOf(TREASURY) == 4_000_000, "fee");
        require(usdc.balanceOf(address(market)) == 0, "conservation");
        vm.expectRevert();
        vm.prank(ALICE);
        settlement.redeemVPT(id, true, 1);
    }

    function testNo80Yes20() public {
        _stake(false);
        _finalize(Settlement.Outcome.No);
        vm.prank(ALICE);
        settlement.redeemVPT(id, false, 80_000_000);
        settlement.claimFee(id);
        require(usdc.balanceOf(ALICE) == 96_000_000, "winner");
    }

    function testOneSidedVoid() public {
        vm.prank(ALICE);
        market.stakeLocal(id, true, 80_000_000, ALICE);
        _finalize(Settlement.Outcome.Yes);
        vm.prank(ALICE);
        settlement.redeemVPT(id, true, 80_000_000);
        require(usdc.balanceOf(ALICE) == 80_000_000, "refund");
        (, Settlement.Outcome finalOutcome,,,,) = settlement.decisions(id);
        require(finalOutcome == Settlement.Outcome.Void, "void");
    }

    function testNoFakeFunds() public {
        vm.expectRevert();
        vm.prank(ALICE);
        market.stakeLocal(id, true, 100_000_000, ALICE);
        require(market.total(id, true) == 0, "unfunded");
    }

    function testPublicationRejectsInvalidAndExpiredApproval() public {
        ReportRegistry.Report memory r = registry.getReport(id);
        uint64 expiry = uint64(block.timestamp + 1 hours);
        (uint8 v, bytes32 a, bytes32 b) = vm.sign(0xBAD, registry.approvalDigest(r, 2, expiry));
        vm.expectRevert();
        registry.publish(r, 2, expiry, abi.encodePacked(a, b, v));
        uint64 expired = uint64(block.timestamp - 1);
        (v, a, b) = vm.sign(REVIEWER_KEY, registry.approvalDigest(r, 3, expired));
        vm.expectRevert();
        registry.publish(r, 3, expired, abi.encodePacked(a, b, v));
        require(registry.reportCount() == 1, "unapproved report opened");
    }

    function testRoundingDustSweptAfterClaimsExpire() public {
        usdc.mint(CAROL, 1);
        vm.prank(CAROL);
        usdc.approve(address(market), 1);
        vm.prank(ALICE);
        market.stakeLocal(id, true, 2, ALICE);
        vm.prank(BOB);
        market.stakeLocal(id, true, 1, BOB);
        vm.prank(CAROL);
        market.stakeLocal(id, false, 1, CAROL);
        _finalize(Settlement.Outcome.Yes);
        vm.prank(ALICE);
        settlement.redeemVPT(id, true, 2);
        vm.prank(BOB);
        settlement.redeemVPT(id, true, 1);
        require(usdc.balanceOf(address(market)) == 1, "dust remains");
        vm.expectRevert();
        settlement.sweepDust(id);
        (,,,, uint64 finalizedAt,) = settlement.decisions(id);
        vm.warp(uint256(finalizedAt) + 90 days + 1);
        settlement.sweepDust(id);
        require(usdc.balanceOf(TREASURY) == 1, "dust swept");
    }

    function testOneREPForOneNullifier() public {
        _stake(true);
        _finalize(Settlement.Outcome.Yes);
        uint256 winningId = positions.tokenId(id, true);
        vm.prank(ALICE);
        positions.safeTransferFrom(ALICE, BOB, winningId, 1_000_000, "");
        bytes32 scoped = keccak256("world-nullifier-scoped-to-report");
        uint64 expiry = uint64(block.timestamp + 1 hours);
        bytes32 digest = reputation.authorizationDigest(id, ALICE, scoped, 9, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(REVIEWER_KEY, digest);
        reputation.claimWinnerREP(id, ALICE, scoped, 9, expiry, abi.encodePacked(r, s, v));
        require(reputation.balanceOf(ALICE, id) == 1, "badge");
        vm.expectRevert();
        reputation.claimWinnerREP(id, ALICE, scoped, 9, expiry, abi.encodePacked(r, s, v));
        digest = reputation.authorizationDigest(id, BOB, scoped, 10, expiry);
        (v, r, s) = vm.sign(REVIEWER_KEY, digest);
        vm.expectRevert();
        reputation.claimWinnerREP(id, BOB, scoped, 10, expiry, abi.encodePacked(r, s, v));
    }
}
