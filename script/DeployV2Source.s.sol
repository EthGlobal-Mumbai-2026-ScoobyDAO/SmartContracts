// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "../src/Utils.sol";
import {IRouterClient} from "chainlink-ccip/interfaces/IRouterClient.sol";
import {CCIPStakeSenderV2} from "../src/v2/CCIPStakeSenderV2.sol";

/// @notice Prepared for review. Do not broadcast until V2 deployment is approved.
contract DeployV2Source is Script {
    function run() external {
        require(block.chainid == 421614, "ARBITRUM_SEPOLIA_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address token = vm.envAddress("ARBITRUM_DEMO_USD");
        address router = vm.envAddress("ARBITRUM_SEPOLIA_CCIP_ROUTER");
        address receiver = vm.envAddress("SEPOLIA_V2_CCIP_RECEIVER");
        uint64 selector = uint64(vm.envUint("ETHEREUM_SEPOLIA_CHAIN_SELECTOR"));
        require(token.code.length > 0 && router.code.length > 0 && receiver != address(0) && selector != 0);
        require(IRouterClient(router).isChainSupported(selector), "UNSUPPORTED_LANE");
        vm.startBroadcast(key);
        CCIPStakeSenderV2 sender = new CCIPStakeSenderV2(IRouterClient(router), IERC20(token), selector, receiver);
        vm.stopBroadcast();
        console2.log("V2Sender", address(sender));
    }
}
