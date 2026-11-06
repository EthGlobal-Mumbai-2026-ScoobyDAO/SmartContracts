// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Script, console2} from "forge-std/Script.sol";
import {Client} from "chainlink-ccip/libraries/Client.sol";
import {IRouterClient} from "chainlink-ccip/interfaces/IRouterClient.sol";
import {ExtraArgsCodec} from "chainlink-ccip/libraries/ExtraArgsCodec.sol";
import {StakeIntent} from "../src/ccip/StakeIntent.sol";

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

contract PreflightSource is Script {
    function run() external view {
        require(block.chainid == 421614, "ARBITRUM_SEPOLIA_ONLY");
        address routerAddress = vm.envAddress("ARBITRUM_SEPOLIA_CCIP_ROUTER");
        address token = vm.envAddress("ARBITRUM_DEMO_USD");
        uint64 destination = uint64(vm.envUint("ETHEREUM_SEPOLIA_CHAIN_SELECTOR"));
        require(routerAddress.code.length > 0 && token.code.length > 0, "CONTRACT_CODE");
        require(IERC20Decimals(token).decimals() == 6, "USDC_DECIMALS");
        IRouterClient router = IRouterClient(routerAddress);
        require(router.isChainSupported(destination), "UNSUPPORTED_LANE");
        Client.EVMTokenAmount[] memory tokens = new Client.EVMTokenAmount[](1);
        tokens[0] = Client.EVMTokenAmount(token, 1_000_000);
        StakeIntent memory intent =
            StakeIntent(1, 1, true, address(0x1234), 1, uint64(block.timestamp + 1 days), 1_000_000);
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(0x1234)),
            data: abi.encode(intent),
            tokenAmounts: tokens,
            feeToken: address(0),
            extraArgs: ExtraArgsCodec._getBasicEncodedExtraArgsV3(500_000, bytes4(0))
        });
        uint256 fee = router.getFee(destination, message);
        console2.log("Arbitrum Sepolia -> Ethereum Sepolia 1 USDC + data fee (wei)", fee);
    }
}
