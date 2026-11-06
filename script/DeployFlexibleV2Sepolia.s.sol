// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "../src/Utils.sol";
import {ReportRegistry} from "../src/ReportRegistry.sol";
import {FlexibleReportRegistry} from "../src/v2/FlexibleReportRegistry.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";
import {CCIPStakeReceiverV2} from "../src/v2/CCIPStakeReceiverV2.sol";

/// @notice Deploy the reusable fast-clock registry and one report's V2 vault/CCIP receiver.
contract DeployFlexibleV2Sepolia is Script {
    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(key);
        IERC20 token = IERC20(vm.envAddress("SEPOLIA_DEMO_USD"));
        address router = vm.envAddress("SEPOLIA_CCIP_ROUTER");
        uint64 selector = uint64(vm.envUint("ARBITRUM_SEPOLIA_CHAIN_SELECTOR"));
        require(address(token).code.length > 0 && router.code.length > 0 && selector != 0, "CONFIG");
        vm.startBroadcast(key);
        FlexibleReportRegistry registry = new FlexibleReportRegistry(deployer);
        RiskFiStakeVaultV2 vault = new RiskFiStakeVaultV2(token, ReportRegistry(address(registry)), deployer, deployer);
        CCIPStakeReceiverV2 receiver = new CCIPStakeReceiverV2(router, selector, token, vault, deployer);
        vm.stopBroadcast();
        console2.log("FlexibleRegistry", address(registry));
        console2.log("V2Vault", address(vault));
        console2.log("V2Receiver", address(receiver));
    }
}
