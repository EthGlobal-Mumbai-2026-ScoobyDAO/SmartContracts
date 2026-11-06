// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Guard} from "./Utils.sol";
import {ReportRegistry} from "./ReportRegistry.sol";
import {VoteMarket} from "./VoteMarket.sol";
import {VotingPositionToken} from "./VotingPositionToken.sol";

contract Settlement is Guard {
    enum Outcome { None, Yes, No, Void }
    struct Decision { Outcome proposed; Outcome finalOutcome; bytes32 evidenceHash; uint64 proposedAt; uint64 finalizedAt; bool challenged; }
    ReportRegistry public immutable registry;
    VoteMarket public immutable market;
    VotingPositionToken public immutable positions;
    address public immutable treasury;
    mapping(uint256 => Decision) public decisions;
    mapping(uint256 => uint256) public claimed;
    mapping(uint256 => uint256) public feePaid;
    event Proposed(uint256 indexed id, Outcome outcome, bytes32 evidenceHash);
    event Challenged(uint256 indexed id, bytes32 evidenceHash);
    event Finalized(uint256 indexed id, Outcome outcome);
    event Redeemed(uint256 indexed id, address indexed holder, bool yes, uint256 burned, uint256 paid);
    constructor(ReportRegistry registry_, VoteMarket market_, VotingPositionToken positions_, address treasury_) {
        registry = registry_; market = market_; positions = positions_; treasury = treasury_;
    }
    function propose(uint256 id, Outcome outcome, bytes32 evidenceHash) external {
        ReportRegistry.Report memory r = registry.getReport(id);
        require(msg.sender == r.resolver && block.timestamp >= uint256(r.lockTime) + 30 days, "RESOLVER_OR_MATURITY");
        require(block.timestamp <= r.resultDeadline && evidenceHash != 0, "EVIDENCE_DEADLINE");
        require(outcome != Outcome.None && decisions[id].proposedAt == 0, "PROPOSAL");
        Decision storage d = decisions[id];
        d.proposed = outcome; d.evidenceHash = evidenceHash; d.proposedAt = uint64(block.timestamp);
        emit Proposed(id, outcome, evidenceHash);
    }
    function challenge(uint256 id, bytes32 evidenceHash) external {
        Decision storage d = decisions[id];
        ReportRegistry.Report memory r = registry.getReport(id);
        require(d.proposedAt != 0 && !d.challenged && block.timestamp < uint256(d.proposedAt) + r.challengePeriod, "CHALLENGE_WINDOW");
        require(evidenceHash != 0, "EVIDENCE");
        d.challenged = true;
        emit Challenged(id, evidenceHash);
    }
    function adjudicate(uint256 id, Outcome outcome, bytes32 evidenceHash) external {
        ReportRegistry.Report memory r = registry.getReport(id);
        Decision storage d = decisions[id];
        require(msg.sender == r.adjudicator && d.challenged && d.finalizedAt == 0, "ADJUDICATOR");
        require(outcome != Outcome.None && evidenceHash != 0 && block.timestamp <= r.resultDeadline, "ADJUDICATION_DEADLINE");
        d.evidenceHash = evidenceHash;
        _finalize(id, outcome);
    }
    function finalize(uint256 id) external {
        ReportRegistry.Report memory r = registry.getReport(id);
        Decision storage d = decisions[id];
        require(r.lockTime != 0 && d.finalizedAt == 0, "REPORT_OR_FINAL");
        if (block.timestamp > r.resultDeadline) { _finalize(id, Outcome.Void); return; }
        require(d.proposedAt != 0 && !d.challenged && block.timestamp >= uint256(d.proposedAt) + r.challengePeriod, "PENDING");
        _finalize(id, d.proposed);
    }
    function _finalize(uint256 id, Outcome outcome) internal {
        uint256 yes = market.total(id, true); uint256 no = market.total(id, false);
        if (yes == 0 || no == 0) outcome = Outcome.Void;
        Decision storage d = decisions[id];
        d.finalOutcome = outcome; d.finalizedAt = uint64(block.timestamp);
        emit Finalized(id, outcome);
    }
    function redeemVPT(uint256 id, bool yes, uint256 amount) external nonReentrant returns (uint256 payout) {
        require(amount > 0, "AMOUNT");
        Outcome outcome = decisions[id].finalOutcome;
        require(outcome != Outcome.None, "NOT_FINAL");
        require(block.timestamp <= uint256(decisions[id].finalizedAt) + 90 days, "CLAIM_EXPIRED");
        uint256 winner = market.total(id, yes);
        uint256 loser = market.total(id, !yes);
        if (outcome == Outcome.Void) payout = amount;
        else if ((outcome == Outcome.Yes) == yes) payout = amount + amount * (loser - loser / 5) / winner;
        positions.burn(msg.sender, positions.tokenId(id, yes), amount);
        claimed[id] += payout;
        if (payout > 0) market.release(id, msg.sender, payout);
        emit Redeemed(id, msg.sender, yes, amount, payout);
    }
    function claimFee(uint256 id) external nonReentrant {
        Outcome outcome = decisions[id].finalOutcome;
        require(outcome == Outcome.Yes || outcome == Outcome.No, "NO_FEE");
        uint256 loser = market.total(id, outcome == Outcome.No);
        uint256 fee = loser / 5;
        require(feePaid[id] == 0 && fee > 0, "FEE_PAID");
        feePaid[id] = fee;
        market.release(id, treasury, fee);
    }
    function sweepDust(uint256 id) external nonReentrant {
        Decision memory d = decisions[id];
        require(d.finalizedAt != 0 && block.timestamp > uint256(d.finalizedAt) + 90 days, "CLAIM_OPEN");
        uint256 total = market.total(id, false) + market.total(id, true);
        uint256 remaining = total - market.principalReleased(id);
        require(remaining > 0, "NO_DUST");
        market.release(id, treasury, remaining);
    }
}
