// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {VoteMarket} from "../src/VoteMarket.sol";
import {YieldSplitter} from "../src/yield/YieldSplitter.sol";
import {CCIPStakeReceiver} from "../src/ccip/CCIPStakeReceiver.sol";
import {CCIPStakeSender} from "../src/ccip/CCIPStakeSender.sol";

contract LiveDeploymentTest is Test {
    function testEthereumSepoliaWiring() public {
        string memory rpc = vm.envOr("ETH_SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        address marketAddress = vm.envAddress("SEPOLIA_MARKET");
        address splitterAddress = vm.envAddress("SEPOLIA_SPLITTER");
        address receiverAddress = vm.envAddress("SEPOLIA_CCIP_RECEIVER");
        address sourceSender = vm.envAddress("ARBITRUM_CCIP_SENDER");
        VoteMarket market = VoteMarket(marketAddress);
        YieldSplitter splitter = YieldSplitter(splitterAddress);
        CCIPStakeReceiver receiver = CCIPStakeReceiver(receiverAddress);

        assertGt(marketAddress.code.length, 0);
        assertEq(market.ccipReceiver(), receiverAddress);
        assertEq(address(market.splitter()), splitterAddress);
        assertEq(address(market.usdc()), vm.envAddress("SEPOLIA_DEMO_USD"));
        assertEq(address(splitter.vault()), vm.envAddress("SEPOLIA_VAULT"));
        assertEq(receiver.sourceSender(), sourceSender);
        assertEq(address(receiver.market()), marketAddress);
        assertEq(address(receiver.usdc()), vm.envAddress("SEPOLIA_DEMO_USD"));
    }

    function testArbitrumSepoliaSenderWiring() public {
        string memory rpc = vm.envOr("ARB_SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        address senderAddress = vm.envAddress("ARBITRUM_CCIP_SENDER");
        CCIPStakeSender sender = CCIPStakeSender(senderAddress);
        assertGt(senderAddress.code.length, 0);
        assertEq(address(sender.router()), vm.envAddress("ARBITRUM_SEPOLIA_CCIP_ROUTER"));
        assertEq(address(sender.sourceUSDC()), vm.envAddress("ARBITRUM_DEMO_USD"));
        assertEq(sender.destinationReceiver(), vm.envAddress("SEPOLIA_CCIP_RECEIVER"));
        assertEq(sender.destinationSelector(), uint64(vm.envUint("ETHEREUM_SEPOLIA_CHAIN_SELECTOR")));
    }
}
