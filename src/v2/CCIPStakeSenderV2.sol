// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20, SafeToken, Guard} from "../Utils.sol";
import {Client} from "chainlink-ccip/libraries/Client.sol";
import {IRouterClient} from "chainlink-ccip/interfaces/IRouterClient.sol";
import {StakeIntentV2} from "./StakeIntentV2.sol";

/// @notice Arbitrum Sepolia source for a V2 funded vote and staker-owned YT.
contract CCIPStakeSenderV2 is Guard {
    using SafeToken for IERC20;

    IRouterClient public immutable router;
    IERC20 public immutable sourceUSD;
    uint64 public immutable destinationSelector;
    address public immutable destinationReceiver;
    address public immutable owner;
    mapping(uint256 => uint64) public reportCutoff;
    mapping(address => mapping(uint256 => bool)) public usedNonce;

    event Sent(
        bytes32 indexed messageId,
        address indexed sourceAccount,
        uint256 indexed reportId,
        address recipient,
        bool yes,
        uint256 amount
    );
    event ReportCutoffConfigured(uint256 indexed reportId, uint64 cutoff);

    constructor(IRouterClient router_, IERC20 sourceUSD_, uint64 selector_, address receiver_) {
        require(
            address(router_) != address(0) && address(sourceUSD_) != address(0) && receiver_ != address(0), "ADDRESS"
        );
        require(selector_ != 0, "SELECTOR");
        router = router_;
        sourceUSD = sourceUSD_;
        destinationSelector = selector_;
        destinationReceiver = receiver_;
        owner = msg.sender;
    }

    function configureReportCutoff(uint256 reportId, uint64 cutoff) external {
        require(
            msg.sender == owner && reportId != 0 && reportCutoff[reportId] == 0 && cutoff > block.timestamp, "CUTOFF"
        );
        reportCutoff[reportId] = cutoff;
        emit ReportCutoffConfigured(reportId, cutoff);
    }

    function _message(StakeIntentV2 memory intent, uint256 amount, bytes memory extraArgs)
        internal
        view
        returns (Client.EVM2AnyMessage memory m)
    {
        Client.EVMTokenAmount[] memory tokens = new Client.EVMTokenAmount[](1);
        tokens[0] = Client.EVMTokenAmount(address(sourceUSD), amount);
        m = Client.EVM2AnyMessage(abi.encode(destinationReceiver), abi.encode(intent), tokens, address(0), extraArgs);
    }

    function quoteFee(StakeIntentV2 calldata intent, uint256 amount, bytes calldata extraArgs)
        external
        view
        returns (uint256)
    {
        require(router.isChainSupported(destinationSelector), "UNSUPPORTED_CHAIN");
        return router.getFee(destinationSelector, _message(intent, amount, extraArgs));
    }

    function stakeRemote(StakeIntentV2 calldata intent, uint256 amount, bytes calldata extraArgs)
        external
        payable
        nonReentrant
        returns (bytes32 messageId)
    {
        require(
            intent.protocolVersion == 2 && intent.sourceAccount == msg.sender && intent.recipient != address(0)
                && amount > 0 && amount >= intent.minAmount,
            "INTENT"
        );
        require(reportCutoff[intent.reportId] != 0 && block.timestamp < reportCutoff[intent.reportId], "REMOTE_CLOSED");
        require(block.timestamp <= intent.deadline && !usedNonce[msg.sender][intent.nonce], "EXPIRED_OR_REPLAY");
        require(router.isChainSupported(destinationSelector), "UNSUPPORTED_CHAIN");
        usedNonce[msg.sender][intent.nonce] = true;
        uint256 beforeBalance = sourceUSD.balanceOf(address(this));
        sourceUSD.safeTransferFrom(msg.sender, address(this), amount);
        require(sourceUSD.balanceOf(address(this)) - beforeBalance == amount, "TOKEN_DELTA");
        Client.EVM2AnyMessage memory m = _message(intent, amount, extraArgs);
        uint256 fee = router.getFee(destinationSelector, m);
        require(msg.value >= fee, "FEE");
        sourceUSD.safeApprove(address(router), 0);
        sourceUSD.safeApprove(address(router), amount);
        messageId = router.ccipSend{value: fee}(destinationSelector, m);
        if (msg.value > fee) {
            (bool ok,) = payable(msg.sender).call{value: msg.value - fee}("");
            require(ok, "REFUND");
        }
        emit Sent(messageId, msg.sender, intent.reportId, intent.recipient, intent.yes, amount);
    }
}
