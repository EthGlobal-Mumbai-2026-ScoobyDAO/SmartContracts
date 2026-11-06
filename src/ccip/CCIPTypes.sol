// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ABI-compatible subset of Chainlink CCIP v2 Client structs. Deployment must be
// checked against the exact router and token route in the current CCIP directory.
library CCIPTypes {
    struct EVMTokenAmount { address token; uint256 amount; }
    struct EVM2AnyMessage { bytes receiver; bytes data; EVMTokenAmount[] tokenAmounts; address feeToken; bytes extraArgs; }
    struct Any2EVMMessage { bytes32 messageId; uint64 sourceChainSelector; bytes sender; bytes data; EVMTokenAmount[] destTokenAmounts; }
    struct StakeIntent {
        uint256 protocolVersion;
        uint256 reportId;
        bool yes;
        address recipient;
        uint256 nonce;
        uint64 deadline;
        uint256 minAmount;
    }
}
interface ICCIPRouter {
    function getFee(uint64 selector, CCIPTypes.EVM2AnyMessage calldata message) external view returns (uint256);
    function ccipSend(uint64 selector, CCIPTypes.EVM2AnyMessage calldata message) external payable returns (bytes32);
}
