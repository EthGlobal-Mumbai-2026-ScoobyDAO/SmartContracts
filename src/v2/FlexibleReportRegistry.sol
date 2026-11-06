// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Sig} from "../Utils.sol";

/// @notice Per-report clocks for accelerated demos. Existing ReportRegistry deployments are unchanged.
/// @dev getReport/maturity match the interface used by RiskFiStakeVaultV2.
contract FlexibleReportRegistry {
    struct Report {
        bytes32 reportHash;
        bytes32 claimHash;
        address reviewer;
        address resolver;
        address adjudicator;
        uint64 lockTime;
        uint64 crossChainCutoff;
        uint64 resultDeadline;
        uint64 challengePeriod;
    }

    address public immutable publisher;
    uint256 public reportCount;
    mapping(uint256 => Report) public reports;
    mapping(uint256 => uint64) public maturityTime;
    mapping(address => mapping(uint256 => bool)) public usedNonce;

    event Published(uint256 indexed reportId, bytes32 reportHash, bytes32 claimHash, address reviewer);
    event ClockConfigured(
        uint256 indexed reportId, uint64 lockTime, uint64 maturity, uint64 resultDeadline, uint64 challengePeriod
    );

    constructor(address publisher_) {
        require(publisher_ != address(0), "PUBLISHER");
        publisher = publisher_;
    }

    function publish(
        Report calldata report,
        uint64 seriesMaturity,
        uint256 nonce,
        uint64 approvalExpiry,
        bytes calldata approval
    ) external returns (uint256 id) {
        require(msg.sender == publisher, "PUBLISHER");
        require(report.reportHash != 0 && report.claimHash != 0 && report.reviewer != address(0), "HASH_OR_REVIEWER");
        require(report.resolver != address(0) && report.adjudicator != address(0), "AUTHORITY");
        require(block.timestamp <= approvalExpiry && !usedNonce[report.reviewer][nonce], "APPROVAL_EXPIRED_OR_USED");
        require(block.timestamp < report.crossChainCutoff && report.crossChainCutoff < report.lockTime, "CUTOFF");
        require(report.lockTime < seriesMaturity && seriesMaturity < report.resultDeadline, "MATURITY");
        require(
            report.challengePeriod > 0 && uint256(seriesMaturity) + report.challengePeriod < report.resultDeadline,
            "RESULT_WINDOW"
        );

        bytes32 hash =
            keccak256(abi.encode(block.chainid, address(this), report, seriesMaturity, nonce, approvalExpiry));
        require(Sig.recover(Sig.ethSigned(hash), approval) == report.reviewer, "REVIEWER");

        usedNonce[report.reviewer][nonce] = true;
        id = ++reportCount;
        reports[id] = report;
        maturityTime[id] = seriesMaturity;
        emit Published(id, report.reportHash, report.claimHash, report.reviewer);
        emit ClockConfigured(id, report.lockTime, seriesMaturity, report.resultDeadline, report.challengePeriod);
    }

    function getReport(uint256 id) external view returns (Report memory) {
        return reports[id];
    }

    function maturity(uint256 id) external view returns (uint256) {
        return maturityTime[id];
    }

    function approvalDigest(Report calldata report, uint64 seriesMaturity, uint256 nonce, uint64 expiry)
        external
        view
        returns (bytes32)
    {
        return Sig.ethSigned(keccak256(abi.encode(block.chainid, address(this), report, seriesMaturity, nonce, expiry)));
    }
}
