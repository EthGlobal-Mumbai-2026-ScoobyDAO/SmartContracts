// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20, SafeToken, Guard} from "../Utils.sol";
import {Client} from "chainlink-ccip/libraries/Client.sol";
import {CCIPReceiver} from "chainlink-ccip/applications/CCIPReceiver.sol";
import {RiskFiStakeVaultV2} from "./RiskFiStakeVaultV2.sol";
import {StakeIntentV2} from "./StakeIntentV2.sol";

/// @notice Credits only delivered CCIP collateral to V2; failed credit stays recoverable.
contract CCIPStakeReceiverV2 is CCIPReceiver, Guard {
    using SafeToken for IERC20;

    address public sourceSender;
    uint64 public immutable sourceSelector;
    IERC20 public immutable usdc;
    RiskFiStakeVaultV2 public immutable vault;
    address public immutable recoveryOperator;
    mapping(bytes32 => bool) public delivered;
    mapping(bytes32 => bool) public usedSourceNonce;
    mapping(bytes32 => uint256) public recoverable;
    mapping(bytes32 => address) public recoverySourceAccount;

    event Credited(bytes32 indexed messageId, uint256 indexed reportId, address indexed recipient, uint256 amount);
    event Held(bytes32 indexed messageId, address indexed sourceAccount, uint256 amount);
    event Recovered(bytes32 indexed messageId, address indexed to, uint256 amount);

    constructor(address router_, uint64 selector_, IERC20 usdc_, RiskFiStakeVaultV2 vault_, address operator_)
        CCIPReceiver(router_)
    {
        require(router_ != address(0) && selector_ != 0 && operator_ != address(0), "CONFIG");
        require(address(usdc_) != address(0) && address(vault_) != address(0), "ADDRESS");
        require(address(vault_.usdc()) == address(usdc_), "TOKEN_MISMATCH");
        sourceSelector = selector_;
        usdc = usdc_;
        vault = vault_;
        recoveryOperator = operator_;
    }

    function configureSourceSender(address sender_) external {
        require(
            msg.sender == recoveryOperator && sourceSender == address(0) && sender_ != address(0), "SOURCE_CONFIGURED"
        );
        sourceSender = sender_;
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override nonReentrant {
        require(message.sourceChainSelector == sourceSelector, "CHAIN");
        require(
            sourceSender != address(0) && keccak256(message.sender) == keccak256(abi.encode(sourceSender)), "SOURCE"
        );
        require(message.messageId != 0 && !delivered[message.messageId], "REPLAY");
        require(message.destTokenAmounts.length == 1, "TOKEN_COUNT");
        Client.EVMTokenAmount memory token = message.destTokenAmounts[0];
        require(token.token == address(usdc) && token.amount > 0, "TOKEN");
        delivered[message.messageId] = true;

        StakeIntentV2 memory intent;
        bool decoded;
        try this.decodeIntent(message.data) returns (StakeIntentV2 memory value) {
            intent = value;
            decoded = true;
        } catch {}
        address sourceAccount = decoded ? intent.sourceAccount : address(0);
        bytes32 nonceKey = keccak256(abi.encode(message.sourceChainSelector, sourceSender, sourceAccount, intent.nonce));
        bool valid = decoded && intent.protocolVersion == 2 && intent.reportId != 0
            && intent.reportId == vault.reportId() && sourceAccount != address(0) && intent.recipient != address(0)
            && token.amount >= intent.minAmount && block.timestamp <= intent.deadline && !usedSourceNonce[nonceKey];
        if (valid) {
            usedSourceNonce[nonceKey] = true;
            usdc.safeApprove(address(vault), 0);
            usdc.safeApprove(address(vault), token.amount);
            try vault.stake(intent.reportId, intent.yes, token.amount, intent.recipient, intent.recipient) {
                emit Credited(message.messageId, intent.reportId, intent.recipient, token.amount);
                return;
            } catch {}
        }
        recoverable[message.messageId] = token.amount;
        recoverySourceAccount[message.messageId] = sourceAccount;
        emit Held(message.messageId, sourceAccount, token.amount);
    }

    function decodeIntent(bytes calldata data) external pure returns (StakeIntentV2 memory) {
        return abi.decode(data, (StakeIntentV2));
    }

    function recover(bytes32 messageId, address to) external nonReentrant {
        uint256 amount = recoverable[messageId];
        address sourceAccount = recoverySourceAccount[messageId];
        require(amount != 0, "NO_FUNDS");
        if (sourceAccount == address(0)) require(msg.sender == recoveryOperator && to != address(0), "OPERATOR");
        else require(msg.sender == sourceAccount && to == sourceAccount, "SOURCE_ACCOUNT");
        recoverable[messageId] = 0;
        usdc.safeTransfer(to, amount);
        emit Recovered(messageId, to, amount);
    }
}
