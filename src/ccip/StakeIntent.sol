// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct StakeIntent {
    uint256 protocolVersion;
    uint256 reportId;
    bool yes;
    address recipient;
    uint256 nonce;
    uint64 deadline;
    uint256 minAmount;
}
