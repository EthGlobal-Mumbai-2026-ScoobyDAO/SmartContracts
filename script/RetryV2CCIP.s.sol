// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {CCIPStakeReceiverV2} from "../src/v2/CCIPStakeReceiverV2.sol";

interface ICCIPOffRampV2 {
    function execute(
        bytes calldata encodedMessage,
        address[] calldata ccvs,
        bytes[] calldata verifierResults,
        uint32 gasLimitOverride
    ) external;
}

/// @notice Retries an already verified CCIP message using the public execution-inputs API response.
/// @dev Pass the JSON via CCIP_EXECUTION_INPUTS_JSON; it contains no private key.
contract RetryV2CCIP is Script {
    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        string memory json = vm.envString("CCIP_EXECUTION_INPUTS_JSON");
        bytes memory encodedMessage = vm.parseJsonBytes(json, ".encodedMessage");
        address[] memory ccvs = vm.parseJsonAddressArray(json, ".verifierAddresses");
        bytes[] memory proofs = vm.parseJsonBytesArray(json, ".ccvData");
        address offRamp = vm.parseJsonAddress(json, ".offramp");
        bytes32 messageId = vm.envBytes32("V2_CCIP_MESSAGE_ID");
        uint32 callbackGas = uint32(vm.envOr("V2_CCIP_RETRY_GAS", uint256(1_500_000)));
        require(keccak256(encodedMessage) == messageId && ccvs.length == proofs.length, "INPUTS");
        require(callbackGas >= 500_000, "GAS_TOO_LOW");
        CCIPStakeReceiverV2 receiver = CCIPStakeReceiverV2(vm.envAddress("SEPOLIA_V2_CCIP_RECEIVER"));
        require(!receiver.delivered(messageId), "ALREADY_DELIVERED");

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        ICCIPOffRampV2(offRamp).execute(encodedMessage, ccvs, proofs, callbackGas);
        vm.stopBroadcast();
        console2.log("CCIP retry message ID");
        console2.logBytes32(messageId);
        console2.log("Receiver delivered", receiver.delivered(messageId));
    }
}
