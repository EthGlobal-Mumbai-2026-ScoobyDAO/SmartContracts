// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ReportRegistry} from "../src/ReportRegistry.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";

contract PublishV2Report is Script {
    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(key);
        ReportRegistry registry = ReportRegistry(vm.envAddress("SEPOLIA_REPORT_REGISTRY"));
        RiskFiStakeVaultV2 vault = RiskFiStakeVaultV2(vm.envAddress("SEPOLIA_V2_VAULT"));
        require(address(registry).code.length > 0 && address(vault).code.length > 0, "CONTRACTS");
        require(registry.publisher() == deployer && vault.admin() == deployer && vault.reportId() == 0, "AUTH");
        uint64 lockTime = uint64(block.timestamp + 3 days);
        uint64 cutoff = uint64(block.timestamp + 2 days);
        uint64 expiry = uint64(block.timestamp + 1 days);
        uint256 nonce = registry.reportCount() + 1;
        ReportRegistry.Report memory report = ReportRegistry.Report({
            reportHash: keccak256("RiskFi V2 testnet demonstration report"),
            claimHash: keccak256("RiskFi V2 Yes or No demo verdict"),
            reviewer: deployer,
            resolver: deployer,
            adjudicator: deployer,
            lockTime: lockTime,
            crossChainCutoff: cutoff,
            resultDeadline: uint64(uint256(lockTime) + 34 days),
            challengePeriod: 1 days
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, registry.approvalDigest(report, nonce, expiry));
        vm.startBroadcast(key);
        uint256 id = registry.publish(report, nonce, expiry, abi.encodePacked(r, s, v));
        vault.initializeSeries(id);
        vm.stopBroadcast();
        console2.log("V2ReportId", id);
        console2.log("V2YT", address(vault.yt()));
        console2.log("LockTime", lockTime);
        console2.log("SourceCutoff", cutoff);
        console2.log("Maturity", vault.maturity());
    }
}
