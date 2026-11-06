// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IERC20, SafeToken, Guard} from "../Utils.sol";
import {Client} from "chainlink-ccip/libraries/Client.sol";
import {IRouterClient} from "chainlink-ccip/interfaces/IRouterClient.sol";
import {StakeIntent} from "./StakeIntent.sol";

contract CCIPStakeSender is Guard {
    using SafeToken for IERC20;
    IRouterClient public immutable router;
    IERC20 public immutable sourceUSDC;
    uint64 public immutable destinationSelector;
    address public immutable destinationReceiver;
    mapping(address => mapping(uint256 => bool)) public usedNonce;
    event Sent(bytes32 indexed messageId, address indexed sender, uint256 indexed reportId, address recipient, bool yes, uint256 amount);
    constructor(IRouterClient router_, IERC20 sourceUSDC_, uint64 selector_, address receiver_) {
        require(address(router_) != address(0) && address(sourceUSDC_) != address(0) && receiver_ != address(0));
        router = router_; sourceUSDC = sourceUSDC_; destinationSelector = selector_; destinationReceiver = receiver_;
    }
    function _message(StakeIntent memory intent, uint256 amount, bytes memory extraArgs) internal view returns (Client.EVM2AnyMessage memory m) {
        Client.EVMTokenAmount[] memory tokens = new Client.EVMTokenAmount[](1);
        tokens[0] = Client.EVMTokenAmount(address(sourceUSDC), amount);
        m = Client.EVM2AnyMessage(abi.encode(destinationReceiver), abi.encode(intent), tokens, address(0), extraArgs);
    }
    function quoteFee(StakeIntent calldata intent, uint256 amount, bytes calldata extraArgs) external view returns (uint256) {
        return router.getFee(destinationSelector, _message(intent, amount, extraArgs));
    }
    function stakeRemote(StakeIntent calldata intent, uint256 amount, bytes calldata extraArgs) external payable nonReentrant returns (bytes32 messageId) {
        require(intent.protocolVersion == 1 && intent.recipient != address(0) && amount > 0 && amount >= intent.minAmount, "INTENT");
        require(block.timestamp <= intent.deadline && !usedNonce[msg.sender][intent.nonce], "EXPIRED_OR_REPLAY");
        usedNonce[msg.sender][intent.nonce] = true;
        uint256 beforeBalance = sourceUSDC.balanceOf(address(this));
        sourceUSDC.safeTransferFrom(msg.sender, address(this), amount);
        require(sourceUSDC.balanceOf(address(this)) - beforeBalance == amount, "TOKEN_DELTA");
        Client.EVM2AnyMessage memory m = _message(intent, amount, extraArgs);
        uint256 fee = router.getFee(destinationSelector, m);
        require(msg.value >= fee, "FEE");
        sourceUSDC.safeApprove(address(router), 0);
        sourceUSDC.safeApprove(address(router), amount);
        messageId = router.ccipSend{value: fee}(destinationSelector, m);
        if (msg.value > fee) { (bool ok,) = payable(msg.sender).call{value: msg.value - fee}(""); require(ok, "REFUND"); }
        emit Sent(messageId, msg.sender, intent.reportId, intent.recipient, intent.yes, amount);
    }
}
