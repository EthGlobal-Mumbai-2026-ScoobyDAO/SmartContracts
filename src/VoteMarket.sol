// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IERC20, SafeToken, Guard} from "./Utils.sol";
import {ReportRegistry} from "./ReportRegistry.sol";
import {VotingPositionToken} from "./VotingPositionToken.sol";

contract VoteMarket is Guard {
    using SafeToken for IERC20;
    IERC20 public immutable usdc;
    ReportRegistry public immutable registry;
    VotingPositionToken public immutable positions;
    address public immutable owner;
    address public settlement;
    address public ccipReceiver;
    mapping(uint256 => uint256[2]) public totals;
    mapping(bytes32 => bool) public creditedMessage;
    mapping(uint256 => uint256) public principalReleased;
    event Staked(uint256 indexed reportId, address indexed recipient, bool yes, uint256 amount, bytes32 messageId);
    constructor(IERC20 usdc_, ReportRegistry registry_, VotingPositionToken positions_) {
        require(address(usdc_) != address(0));
        owner = msg.sender; usdc = usdc_; registry = registry_; positions = positions_;
    }
    function configure(address settlement_, address ccipReceiver_) external {
        require(msg.sender == owner && settlement == address(0) && ccipReceiver == address(0), "CONFIGURED");
        require(settlement_ != address(0) && ccipReceiver_ != address(0), "ADDRESS");
        settlement = settlement_; ccipReceiver = ccipReceiver_;
    }
    function stakeLocal(uint256 id, bool yes, uint256 amount, address recipient) external nonReentrant {
        require(amount > 0 && recipient != address(0), "STAKE");
        ReportRegistry.Report memory report = registry.getReport(id);
        require(report.lockTime != 0 && block.timestamp < report.lockTime, "CLOSED");
        uint256 beforeBalance = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        require(usdc.balanceOf(address(this)) - beforeBalance == amount, "TOKEN_DELTA");
        _credit(id, yes, amount, recipient, bytes32(0));
    }
    function creditCCIP(uint256 id, bool yes, uint256 amount, address recipient, bytes32 messageId) external nonReentrant {
        require(msg.sender == ccipReceiver && messageId != 0 && !creditedMessage[messageId], "CCIP_AUTH");
        require(recipient != address(0) && amount > 0, "STAKE");
        ReportRegistry.Report memory report = registry.getReport(id);
        require(report.lockTime != 0 && block.timestamp < report.lockTime, "CLOSED");
        uint256 beforeBalance = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        require(usdc.balanceOf(address(this)) - beforeBalance == amount, "TOKEN_DELTA");
        creditedMessage[messageId] = true;
        _credit(id, yes, amount, recipient, messageId);
    }
    function _credit(uint256 id, bool yes, uint256 amount, address recipient, bytes32 messageId) internal {
        totals[id][yes ? 1 : 0] += amount;
        positions.mint(recipient, positions.tokenId(id, yes), amount);
        emit Staked(id, recipient, yes, amount, messageId);
    }
    function release(uint256 id, address recipient, uint256 amount) external nonReentrant {
        require(msg.sender == settlement, "SETTLEMENT");
        require(recipient != address(0), "RECIPIENT");
        uint256 total = totals[id][0] + totals[id][1];
        principalReleased[id] += amount;
        require(principalReleased[id] <= total, "INSOLVENT");
        usdc.safeTransfer(recipient, amount);
    }
    function total(uint256 id, bool yes) external view returns (uint256) { return totals[id][yes ? 1 : 0]; }
}
