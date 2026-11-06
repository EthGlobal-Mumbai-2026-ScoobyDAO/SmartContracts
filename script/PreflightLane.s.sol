// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Script, console2} from "forge-std/Script.sol";
import {IRouterClient} from "chainlink-ccip/interfaces/IRouterClient.sol";

contract PreflightLane is Script {
    function run() external view {
        require(block.chainid == 421614, "ARBITRUM_SEPOLIA_ONLY");
        address router = vm.envAddress("ARBITRUM_SEPOLIA_CCIP_ROUTER");
        uint64 selector = uint64(vm.envUint("ETHEREUM_SEPOLIA_CHAIN_SELECTOR"));
        require(router.code.length > 0, "ROUTER_NOT_DEPLOYED");
        require(IRouterClient(router).isChainSupported(selector), "NO_ARBITRUM_TO_ETHEREUM_LANE");
        console2.log("Arbitrum Sepolia to Ethereum Sepolia CCIP lane supported");
    }
}
