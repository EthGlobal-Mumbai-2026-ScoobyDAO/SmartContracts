// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IERC20, SafeToken, Guard} from "../Utils.sol";
import {VoteMarket} from "../VoteMarket.sol";
import {ReportRegistry} from "../ReportRegistry.sol";
import {Client} from "chainlink-ccip/libraries/Client.sol";
import {CCIPReceiver} from "chainlink-ccip/applications/CCIPReceiver.sol";
import {StakeIntent} from "./StakeIntent.sol";

contract CCIPStakeReceiver is CCIPReceiver, Guard {
    using SafeToken for IERC20;
    address public sourceSender;
    uint64 public immutable sourceSelector;
    IERC20 public immutable usdc;
    VoteMarket public immutable market;
    ReportRegistry public immutable registry;
    address public immutable recoveryOperator;
    mapping(bytes32 => bool) public delivered;
    mapping(bytes32 => uint256) public recoverable;
    mapping(bytes32 => address) public recoveryRecipient;
    mapping(bytes32 => bool) public usedSourceNonce;
    event Credited(bytes32 indexed messageId, uint256 indexed reportId, address indexed recipient, uint256 amount);
    event Held(bytes32 indexed messageId, address indexed recipient, uint256 amount);
    event Recovered(bytes32 indexed messageId, address indexed recipient, uint256 amount);
    constructor(address router_, uint64 selector_, address sender_, IERC20 usdc_, VoteMarket market_, ReportRegistry registry_, address operator_) CCIPReceiver(router_) {
        require(router_ != address(0) && operator_ != address(0));
        sourceSelector = selector_; sourceSender = sender_; usdc = usdc_; market = market_; registry = registry_; recoveryOperator = operator_;
    }
    function configureSourceSender(address sender_) external {
        require(msg.sender == recoveryOperator && sourceSender == address(0) && sender_ != address(0), "SOURCE_CONFIGURED");
        sourceSender = sender_;
    }
    // Chainlink router calls this entry point after transferring destTokenAmounts.
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override nonReentrant {
        require(message.sourceChainSelector == sourceSelector, "CHAIN");
        require(keccak256(message.sender) == keccak256(abi.encode(sourceSender)), "SOURCE");
        require(!delivered[message.messageId] && message.messageId != 0, "REPLAY");
        require(message.destTokenAmounts.length == 1, "TOKEN_COUNT");
        Client.EVMTokenAmount memory token = message.destTokenAmounts[0];
        require(token.token == address(usdc) && token.amount > 0, "TOKEN");
        delivered[message.messageId] = true;
        StakeIntent memory intent;
        bool decoded;
        try this.decodeIntent(message.data) returns (StakeIntent memory value) { intent = value; decoded = true; } catch {}
        address recipient = decoded ? intent.recipient : address(0);
        bytes32 nonceKey = keccak256(abi.encode(message.sourceChainSelector, sourceSender, intent.nonce));
        ReportRegistry.Report memory report = registry.getReport(intent.reportId);
        bool valid = decoded && intent.protocolVersion == 1 && recipient != address(0)
            && token.amount >= intent.minAmount && block.timestamp <= intent.deadline
            && report.lockTime != 0 && block.timestamp < report.lockTime && !usedSourceNonce[nonceKey];
        if (valid) {
            usedSourceNonce[nonceKey] = true;
            usdc.safeApprove(address(market), 0);
            usdc.safeApprove(address(market), token.amount);
            try market.creditCCIP(intent.reportId, intent.yes, token.amount, recipient, message.messageId) {
                emit Credited(message.messageId, intent.reportId, recipient, token.amount);
                return;
            } catch {}
        }
        recoverable[message.messageId] = token.amount;
        recoveryRecipient[message.messageId] = recipient;
        emit Held(message.messageId, recipient, token.amount);
    }
    function decodeIntent(bytes calldata data) external pure returns (StakeIntent memory) {
        return abi.decode(data, (StakeIntent));
    }
    function recover(bytes32 messageId, address to) external nonReentrant {
        uint256 amount = recoverable[messageId];
        address recipient = recoveryRecipient[messageId];
        require(amount != 0, "NO_FUNDS");
        if (recipient == address(0)) require(msg.sender == recoveryOperator && to != address(0), "OPERATOR");
        else require(msg.sender == recipient && to == recipient, "RECIPIENT");
        recoverable[messageId] = 0;
        usdc.safeTransfer(to, amount);
        emit Recovered(messageId, to, amount);
    }
}
