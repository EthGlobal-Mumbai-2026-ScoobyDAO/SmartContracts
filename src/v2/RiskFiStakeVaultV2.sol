// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20, SafeToken, Guard} from "../Utils.sol";
import {ReportRegistry} from "../ReportRegistry.sol";
import {StakerYieldToken} from "./StakerYieldToken.sol";

/// @notice One reviewed report: non-transferable verdict positions and staker-owned YT.
/// Collateral stays here; yield injection and principal loss are simulated demo actions.
contract RiskFiStakeVaultV2 is Guard {
    using SafeToken for IERC20;

    enum Outcome {
        None,
        Yes,
        No,
        Void
    }
    IERC20 public immutable usdc;
    ReportRegistry public immutable registry;
    address public immutable admin;
    address public immutable treasury;
    uint256 public reportId;
    uint64 public maturity;
    StakerYieldToken public yt;
    uint256 public totalYes;
    uint256 public totalNo;
    mapping(address => mapping(bool => uint256)) public positionOf;
    Outcome public proposed;
    Outcome public finalOutcome;
    bytes32 public evidenceHash;
    uint64 public proposedAt;
    uint64 public finalizedAt;
    bool public challenged;
    uint256 public principalAvailable;
    uint256 public nominalReleased;
    uint256 public actualPaid;
    bool public feeClaimed;

    event SeriesInitialized(uint256 indexed reportId, address yt, uint64 maturity);
    event Staked(address indexed owner, bool indexed yes, uint256 amount, address ytReceiver);
    event YieldInjected(uint256 amount);
    event LossSimulated(uint256 amount);
    event Proposed(Outcome outcome, bytes32 evidenceHash);
    event Finalized(Outcome outcome, uint256 principalAvailable);
    event PrincipalClaimed(address indexed owner, bool yes, uint256 amount, uint256 paid);

    constructor(IERC20 usdc_, ReportRegistry registry_, address admin_, address treasury_) {
        require(address(usdc_) != address(0) && address(registry_) != address(0), "ADDRESS");
        require(admin_ != address(0) && treasury_ != address(0), "AUTHORITY");
        usdc = usdc_;
        registry = registry_;
        admin = admin_;
        treasury = treasury_;
    }

    function initializeSeries(uint256 id) external {
        require(reportId == 0 && id != 0, "INITIALIZED");
        ReportRegistry.Report memory r = registry.getReport(id);
        require(r.lockTime > block.timestamp, "REPORT");
        reportId = id;
        maturity = uint64(uint256(r.lockTime) + 30 days);
        yt = new StakerYieldToken(usdc, address(this), maturity);
        emit SeriesInitialized(id, address(yt), maturity);
    }

    /// @dev The payer is msg.sender. A router can pay while crediting another owner.
    function stake(uint256 id, bool yes, uint256 amount, address positionOwner, address ytReceiver)
        external
        nonReentrant
        returns (uint256)
    {
        require(id == reportId && id != 0 && amount > 0, "SERIES_OR_AMOUNT");
        require(positionOwner != address(0) && ytReceiver != address(0), "RECIPIENT");
        require(block.timestamp < registry.getReport(id).lockTime, "CLOSED");
        uint256 beforeBalance = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        require(usdc.balanceOf(address(this)) - beforeBalance == amount, "TOKEN_DELTA");
        positionOf[positionOwner][yes] += amount;
        if (yes) totalYes += amount;
        else totalNo += amount;
        yt.mint(ytReceiver, amount);
        emit Staked(positionOwner, yes, amount, ytReceiver);
        return amount;
    }

    /// @notice Clearly simulated collateral-token yield for the demo.
    function injectYield(uint256 amount) external nonReentrant {
        require(reportId != 0 && totalYes + totalNo > 0 && block.timestamp < maturity && amount > 0, "YIELD");
        uint256 beforeBalance = usdc.balanceOf(address(yt));
        usdc.safeTransferFrom(msg.sender, address(yt), amount);
        require(usdc.balanceOf(address(yt)) - beforeBalance == amount, "TOKEN_DELTA");
        yt.notifyYield(amount);
        emit YieldInjected(amount);
    }

    function simulateLoss(address sink, uint256 amount) external nonReentrant {
        require(msg.sender == admin && sink != address(0) && finalizedAt == 0, "LOSS_AUTH");
        usdc.safeTransfer(sink, amount);
        emit LossSimulated(amount);
    }

    function propose(Outcome outcome, bytes32 evidence) external {
        ReportRegistry.Report memory r = registry.getReport(reportId);
        require(
            msg.sender == r.resolver && block.timestamp >= maturity && block.timestamp <= r.resultDeadline, "RESOLVER"
        );
        require(outcome != Outcome.None && proposedAt == 0 && evidence != 0, "PROPOSAL");
        proposed = outcome;
        evidenceHash = evidence;
        proposedAt = uint64(block.timestamp);
        emit Proposed(outcome, evidence);
    }

    function challenge(bytes32 evidence) external {
        ReportRegistry.Report memory r = registry.getReport(reportId);
        require(
            proposedAt != 0 && !challenged && block.timestamp < uint256(proposedAt) + r.challengePeriod, "CHALLENGE"
        );
        require(evidence != 0, "EVIDENCE");
        challenged = true;
    }

    function adjudicate(Outcome outcome, bytes32 evidence) external {
        ReportRegistry.Report memory r = registry.getReport(reportId);
        require(msg.sender == r.adjudicator && challenged && finalizedAt == 0, "ADJUDICATOR");
        require(outcome != Outcome.None && evidence != 0 && block.timestamp <= r.resultDeadline, "ADJUDICATION");
        evidenceHash = evidence;
        _finalize(outcome);
    }

    function finalize() external {
        ReportRegistry.Report memory r = registry.getReport(reportId);
        require(reportId != 0 && finalizedAt == 0, "FINAL");
        if (block.timestamp > r.resultDeadline) {
            _finalize(Outcome.Void);
            return;
        }
        require(proposedAt != 0 && !challenged && block.timestamp >= uint256(proposedAt) + r.challengePeriod, "PENDING");
        _finalize(proposed);
    }

    function _finalize(Outcome outcome) internal {
        if (totalYes == 0 || totalNo == 0) outcome = Outcome.Void;
        finalOutcome = outcome;
        finalizedAt = uint64(block.timestamp);
        yt.mature();
        uint256 totalPrincipal = totalYes + totalNo;
        principalAvailable = usdc.balanceOf(address(this));
        if (principalAvailable > totalPrincipal) principalAvailable = totalPrincipal;
        emit Finalized(outcome, principalAvailable);
    }

    function _release(address to, uint256 nominal) internal returns (uint256 paid) {
        uint256 totalPrincipal = totalYes + totalNo;
        nominalReleased += nominal;
        require(nominalReleased <= totalPrincipal, "INSOLVENT");
        paid = nominal * principalAvailable / totalPrincipal;
        actualPaid += paid;
        if (paid != 0) usdc.safeTransfer(to, paid);
    }

    function claimPrincipal(bool yes, uint256 amount) external nonReentrant returns (uint256 paid) {
        require(finalOutcome != Outcome.None && amount > 0, "NOT_FINAL");
        require(block.timestamp <= uint256(finalizedAt) + 90 days, "EXPIRED");
        positionOf[msg.sender][yes] -= amount;
        uint256 nominal;
        if (finalOutcome == Outcome.Void) {
            nominal = amount;
        } else if ((finalOutcome == Outcome.Yes) == yes) {
            uint256 winner = yes ? totalYes : totalNo;
            uint256 loser = yes ? totalNo : totalYes;
            nominal = amount + amount * (loser - loser / 5) / winner;
        }
        if (nominal != 0) paid = _release(msg.sender, nominal);
        emit PrincipalClaimed(msg.sender, yes, amount, paid);
    }

    function claimFee() external nonReentrant returns (uint256 paid) {
        require((finalOutcome == Outcome.Yes || finalOutcome == Outcome.No) && !feeClaimed, "FEE");
        require(block.timestamp <= uint256(finalizedAt) + 90 days, "EXPIRED");
        feeClaimed = true;
        uint256 loser = finalOutcome == Outcome.Yes ? totalNo : totalYes;
        paid = _release(treasury, loser / 5);
    }

    function sweepDust() external nonReentrant {
        require(finalizedAt != 0 && block.timestamp > uint256(finalizedAt) + 90 days, "CLAIM_OPEN");
        nominalReleased = totalYes + totalNo;
        actualPaid = principalAvailable;
        uint256 amount = usdc.balanceOf(address(this));
        if (amount != 0) usdc.safeTransfer(treasury, amount);
    }
}
