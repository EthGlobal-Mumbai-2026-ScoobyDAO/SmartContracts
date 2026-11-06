// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {FlexibleReportRegistry} from "../src/v2/FlexibleReportRegistry.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";

/// @notice Start the short demo clock only after the app, CCIP lane and deployer are ready.
contract PublishFlexibleV2Report is Script {
    struct ClockConfig {
        uint64 voteSeconds;
        uint64 tradeSeconds;
        uint64 challengeSeconds;
        uint64 resultSeconds;
        uint64 remoteSeconds;
        uint64 startedAt;
    }

    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(key);
        FlexibleReportRegistry registry = FlexibleReportRegistry(vm.envAddress("SEPOLIA_REPORT_REGISTRY"));
        RiskFiStakeVaultV2 vault = RiskFiStakeVaultV2(vm.envAddress("SEPOLIA_V2_VAULT"));
        require(registry.publisher() == deployer && vault.admin() == deployer && vault.reportId() == 0, "AUTH");

        ClockConfig memory c = ClockConfig({
            voteSeconds: uint64(vm.envUint("V2_VOTE_SECONDS")),
            tradeSeconds: uint64(vm.envUint("V2_TRADE_SECONDS")),
            challengeSeconds: uint64(vm.envUint("V2_CHALLENGE_SECONDS")),
            resultSeconds: uint64(vm.envUint("V2_RESULT_SECONDS")),
            remoteSeconds: uint64(vm.envUint("V2_REMOTE_CUTOFF_SECONDS")),
            startedAt: uint64(block.timestamp)
        });
        require(c.remoteSeconds > 0 && c.remoteSeconds < c.voteSeconds && c.voteSeconds < c.tradeSeconds, "CLOCK");
        require(c.challengeSeconds > 0 && c.tradeSeconds + c.challengeSeconds < c.resultSeconds, "RESULT_CLOCK");
        uint256 nonce = registry.reportCount() + 1;
        FlexibleReportRegistry.Report memory report = FlexibleReportRegistry.Report({
            reportHash: sha256(vm.readFileBinary("demo/accelerated-report.json")),
            claimHash: keccak256("RiskFi accelerated demo: does the test claim resolve Yes?"),
            reviewer: deployer,
            resolver: deployer,
            adjudicator: deployer,
            lockTime: c.startedAt + c.voteSeconds,
            crossChainCutoff: c.startedAt + c.remoteSeconds,
            resultDeadline: c.startedAt + c.resultSeconds,
            challengePeriod: c.challengeSeconds
        });
        uint64 maturityTime = c.startedAt + c.tradeSeconds;
        uint64 expiry = c.startedAt + c.remoteSeconds;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, registry.approvalDigest(report, maturityTime, nonce, expiry));
        vm.startBroadcast(key);
        uint256 id = registry.publish(report, maturityTime, nonce, expiry, abi.encodePacked(r, s, v));
        vault.initializeSeries(id);
        vm.stopBroadcast();
        console2.log("ReportId", id);
        console2.log("YT", address(vault.yt()));
        console2.log("ReportHash", uint256(report.reportHash));
        console2.log("ClaimHash", uint256(report.claimHash));
        console2.log("RemoteCutoff", report.crossChainCutoff);
        console2.log("VoteLock", report.lockTime);
        console2.log("Maturity", maturityTime);
        console2.log("ResultDeadline", report.resultDeadline);
    }
}
