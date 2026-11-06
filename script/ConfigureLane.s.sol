// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Script} from "forge-std/Script.sol";
import {CCIPStakeReceiver} from "../src/ccip/CCIPStakeReceiver.sol";

contract ConfigureLane is Script {
    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address receiver = vm.envAddress("SEPOLIA_CCIP_RECEIVER");
        address sender = vm.envAddress("ARBITRUM_CCIP_SENDER");
        require(receiver.code.length > 0 && sender != address(0), "PRECHECK");
        vm.startBroadcast(key);
        CCIPStakeReceiver(receiver).configureSourceSender(sender);
        vm.stopBroadcast();
    }
}
