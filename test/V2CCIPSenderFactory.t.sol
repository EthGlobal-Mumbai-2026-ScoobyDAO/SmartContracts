// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {V2CCIPSenderFactory} from "../src/v2/V2CCIPSenderFactory.sol";
import {CCIPStakeSenderV2} from "../src/v2/CCIPStakeSenderV2.sol";
import {IERC20} from "../src/Utils.sol";
import {IRouterClient} from "chainlink-ccip/interfaces/IRouterClient.sol";

contract V2CCIPSenderFactoryTest is Test {
    function testDeployWiresReceiverAndCutoff() public {
        V2CCIPSenderFactory f = new V2CCIPSenderFactory(
            address(this), IRouterClient(address(0x1234)), IERC20(address(0x5678)), 16015286601757825753
        );
        address receiver = address(0xABCD);
        address sender = f.deploy(receiver, 7, uint64(block.timestamp + 100));
        assertEq(f.senderForReceiver(receiver), sender);
        assertEq(CCIPStakeSenderV2(sender).destinationReceiver(), receiver);
        assertEq(CCIPStakeSenderV2(sender).reportCutoff(7), block.timestamp + 100);
        vm.expectRevert();
        f.deploy(receiver, 7, uint64(block.timestamp + 200));
    }
}
