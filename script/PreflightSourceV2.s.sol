// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Client} from "chainlink-ccip/libraries/Client.sol";
import {IRouterClient} from "chainlink-ccip/interfaces/IRouterClient.sol";
import {ExtraArgsCodec} from "chainlink-ccip/libraries/ExtraArgsCodec.sol";
import {StakeIntentV2} from "../src/v2/StakeIntentV2.sol";

interface IERC20DecimalsV2 {
    function decimals() external view returns (uint8);
}

/// @notice Read-only live router quote for V2's token-plus-data message shape.
contract PreflightSourceV2 is Script {
    function run() external view {
        require(block.chainid == 421614, "ARBITRUM_SEPOLIA_ONLY");
        address routerAddress = vm.envAddress("ARBITRUM_SEPOLIA_CCIP_ROUTER");
        address token = vm.envAddress("ARBITRUM_DEMO_USD");
        uint64 destination = uint64(vm.envUint("ETHEREUM_SEPOLIA_CHAIN_SELECTOR"));
        require(routerAddress.code.length > 0 && token.code.length > 0, "CONTRACT_CODE");
        require(IERC20DecimalsV2(token).decimals() == 6, "TOKEN_DECIMALS");
        IRouterClient router = IRouterClient(routerAddress);
        require(router.isChainSupported(destination), "UNSUPPORTED_LANE");
        Client.EVMTokenAmount[] memory tokens = new Client.EVMTokenAmount[](1);
        tokens[0] = Client.EVMTokenAmount(token, 1_000_000);
        StakeIntentV2 memory intent = StakeIntentV2({
            protocolVersion: 2,
            reportId: 1,
            yes: true,
            sourceAccount: address(0xAA),
            recipient: address(0xBB),
            nonce: 1,
            deadline: uint64(block.timestamp + 1 days),
            minAmount: 1_000_000
        });
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(0x1234)), // quote placeholder; V2 receiver not deployed
            data: abi.encode(intent),
            tokenAmounts: tokens,
            feeToken: address(0),
            extraArgs: ExtraArgsCodec._getBasicEncodedExtraArgsV3(1_500_000, bytes4(0))
        });
        uint256 fee = router.getFee(destination, message);
        console2.log("V2 Arbitrum Sepolia -> Ethereum Sepolia 1 dUSD + data fee (wei)", fee);
    }
}
