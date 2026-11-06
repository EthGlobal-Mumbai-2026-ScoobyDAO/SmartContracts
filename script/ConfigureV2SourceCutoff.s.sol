// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {CCIPStakeSenderV2} from "../src/v2/CCIPStakeSenderV2.sol";

contract ConfigureV2SourceCutoff is Script {
    function run() external {
        require(block.chainid == 421614, "ARBITRUM_SEPOLIA_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        CCIPStakeSenderV2 sender = CCIPStakeSenderV2(vm.envAddress("ARBITRUM_V2_CCIP_SENDER"));
        uint256 reportId = vm.envUint("V2_REPORT_ID");
        uint64 cutoff = uint64(vm.envUint("V2_SOURCE_CUTOFF"));
        require(address(sender).code.length > 0 && sender.owner() == vm.addr(key), "SENDER");
        vm.startBroadcast(key);
        sender.configureReportCutoff(reportId, cutoff);
        vm.stopBroadcast();
    }
}
