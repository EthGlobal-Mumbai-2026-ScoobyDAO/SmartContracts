// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {CCIPStakeReceiverV2} from "../src/v2/CCIPStakeReceiverV2.sol";

/// @notice One-time sender allowlist after both V2 contracts are reviewed and deployed.
contract ConfigureV2Lane is Script {
    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address receiver = vm.envAddress("SEPOLIA_V2_CCIP_RECEIVER");
        address sender = vm.envAddress("ARBITRUM_V2_CCIP_SENDER");
        require(receiver.code.length > 0 && sender != address(0), "CONFIG");
        vm.startBroadcast(key);
        CCIPStakeReceiverV2(receiver).configureSourceSender(sender);
        vm.stopBroadcast();
    }
}
