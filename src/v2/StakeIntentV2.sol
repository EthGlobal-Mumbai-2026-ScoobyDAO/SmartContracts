// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Source payer is explicit so nonces and failed-fund recovery are per payer.
struct StakeIntentV2 {
    uint8 protocolVersion;
    uint256 reportId;
    bool yes;
    address sourceAccount;
    address recipient;
    uint256 nonce;
    uint64 deadline;
    uint256 minAmount;
}
