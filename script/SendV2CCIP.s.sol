// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "../src/Utils.sol";
import {ExtraArgsCodec} from "chainlink-ccip/libraries/ExtraArgsCodec.sol";
import {CCIPStakeSenderV2} from "../src/v2/CCIPStakeSenderV2.sol";
import {StakeIntentV2} from "../src/v2/StakeIntentV2.sol";

contract SendV2CCIP is Script {
    function run() external {
        require(block.chainid == 421614, "ARBITRUM_SEPOLIA_ONLY");
        uint256 signer = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address wallet = vm.addr(signer);
        CCIPStakeSenderV2 sender = CCIPStakeSenderV2(vm.envAddress("ARBITRUM_V2_CCIP_SENDER"));
        IERC20 token = sender.sourceUSD();
        uint256 reportId = vm.envUint("V2_REPORT_ID");
        uint256 amount = vm.envOr("V2_CCIP_AMOUNT", uint256(5_000_000));
        uint256 callbackGas = vm.envOr("V2_CCIP_GAS_LIMIT", uint256(1_500_000));
        require(amount > 0 && callbackGas <= type(uint32).max, "INPUT");
        require(sender.reportCutoff(reportId) > block.timestamp && token.balanceOf(wallet) >= amount, "FUNDS");
        StakeIntentV2 memory intent = StakeIntentV2({
            protocolVersion: 2,
            reportId: reportId,
            yes: false,
            sourceAccount: wallet,
            recipient: wallet,
            nonce: vm.envOr("V2_CCIP_NONCE", uint256(1)),
            deadline: uint64(block.timestamp + 1 days),
            minAmount: amount
        });
        bytes memory extraArgs = ExtraArgsCodec._getBasicEncodedExtraArgsV3(uint32(callbackGas), bytes4(0));
        uint256 fee = sender.quoteFee(intent, amount, extraArgs);
        console2.log("CCIPFeeWei", fee);
        vm.startBroadcast(signer);
        token.approve(address(sender), amount);
        bytes32 messageId = sender.stakeRemote{value: fee}(intent, amount, extraArgs);
        vm.stopBroadcast();
        console2.logBytes32(messageId);
    }
}
