// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {YieldCurveFactoryV2} from "../src/v2/YieldCurveFactoryV2.sol";

contract DeployV2Factory is Script {
    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        YieldCurveFactoryV2 factory = new YieldCurveFactoryV2(vm.addr(key));
        vm.stopBroadcast();
        console2.log("V2Factory", address(factory));
    }
}
