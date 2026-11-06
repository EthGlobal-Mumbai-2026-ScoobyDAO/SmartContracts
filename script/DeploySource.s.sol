// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "../src/Utils.sol";
import {IRouterClient} from "chainlink-ccip/interfaces/IRouterClient.sol";
import {CCIPStakeSender} from "../src/ccip/CCIPStakeSender.sol";

contract DeploySource is Script {
    function run() external {
        require(block.chainid == 421614, "ARBITRUM_SEPOLIA_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address usdc = vm.envAddress("ARBITRUM_DEMO_USD");
        address router = vm.envAddress("ARBITRUM_SEPOLIA_CCIP_ROUTER");
        address receiver = vm.envAddress("SEPOLIA_CCIP_RECEIVER");
        uint64 selector = uint64(vm.envUint("ETHEREUM_SEPOLIA_CHAIN_SELECTOR"));
        require(usdc.code.length > 0 && router.code.length > 0 && receiver != address(0) && selector != 0, "PRECHECK");
        require(IRouterClient(router).isChainSupported(selector), "UNSUPPORTED_LANE");
        vm.startBroadcast(key);
        CCIPStakeSender sender = new CCIPStakeSender(IRouterClient(router), IERC20(usdc), selector, receiver);
        vm.stopBroadcast();
        console2.log("CCIPSender", address(sender));
    }
}
