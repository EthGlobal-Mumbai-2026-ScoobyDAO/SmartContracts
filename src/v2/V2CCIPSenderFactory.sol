// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "../Utils.sol";
import {IRouterClient} from "chainlink-ccip/interfaces/IRouterClient.sol";
import {CCIPStakeSenderV2} from "./CCIPStakeSenderV2.sol";

/// @notice Arbitrum Sepolia publisher deploys a sender for each destination receiver.
contract V2CCIPSenderFactory {
    address public immutable owner;
    IRouterClient public immutable router;
    IERC20 public immutable usd;
    uint64 public immutable destinationSelector;
    mapping(address => address) public senderForReceiver;
    event SenderDeployed(address indexed receiver, address indexed sender, uint256 reportId, uint64 cutoff);

    constructor(address owner_, IRouterClient router_, IERC20 usd_, uint64 destinationSelector_) {
        require(
            owner_ != address(0) && address(router_) != address(0) && address(usd_) != address(0)
                && destinationSelector_ != 0,
            "CONFIG"
        );
        owner = owner_;
        router = router_;
        usd = usd_;
        destinationSelector = destinationSelector_;
    }

    function deploy(address receiver, uint256 reportId, uint64 cutoff) external returns (address sender) {
        require(
            msg.sender == owner && receiver != address(0) && senderForReceiver[receiver] == address(0), "OWNER_OR_STATE"
        );
        CCIPStakeSenderV2 s = new CCIPStakeSenderV2(router, usd, destinationSelector, receiver);
        s.configureReportCutoff(reportId, cutoff);
        sender = address(s);
        senderForReceiver[receiver] = sender;
        emit SenderDeployed(receiver, sender, reportId, cutoff);
    }
}
