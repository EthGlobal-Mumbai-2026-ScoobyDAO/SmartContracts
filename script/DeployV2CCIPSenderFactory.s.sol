// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Script} from "forge-std/Script.sol";
import {IERC20} from "../src/Utils.sol";
import {IRouterClient} from "chainlink-ccip/interfaces/IRouterClient.sol";
import {V2CCIPSenderFactory} from "../src/v2/V2CCIPSenderFactory.sol";

contract DeployV2CCIPSenderFactory is Script {
    function run() external {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        new V2CCIPSenderFactory(
            vm.addr(key),
            IRouterClient(vm.envAddress("ARBITRUM_SEPOLIA_CCIP_ROUTER")),
            IERC20(vm.envAddress("ARBITRUM_DEMO_USD")),
            uint64(vm.envUint("ETHEREUM_SEPOLIA_CHAIN_SELECTOR"))
        );
        vm.stopBroadcast();
    }
}
