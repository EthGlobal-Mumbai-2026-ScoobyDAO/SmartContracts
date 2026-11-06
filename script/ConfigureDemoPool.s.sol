// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Script} from "forge-std/Script.sol";
import {BurnMintTokenPool} from "chainlink-ccip/pools/BurnMintTokenPool.sol";
import {TokenPool} from "chainlink-ccip/pools/TokenPool.sol";
import {RateLimiter} from "chainlink-ccip/libraries/RateLimiter.sol";

contract ConfigureDemoPool is Script {
    function run() external {
        require(block.chainid == 11155111 || block.chainid == 421614, "TESTNET_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        bool ethereum = block.chainid == 11155111;
        address localToken = vm.envAddress(ethereum ? "SEPOLIA_DEMO_USD" : "ARBITRUM_DEMO_USD");
        address localPool = vm.envAddress(ethereum ? "SEPOLIA_DEMO_POOL" : "ARBITRUM_DEMO_POOL");
        address remoteToken = vm.envAddress(ethereum ? "ARBITRUM_DEMO_USD" : "SEPOLIA_DEMO_USD");
        address remotePool = vm.envAddress(ethereum ? "ARBITRUM_DEMO_POOL" : "SEPOLIA_DEMO_POOL");
        uint64 remoteSelector =
            uint64(vm.envUint(ethereum ? "ARBITRUM_SEPOLIA_CHAIN_SELECTOR" : "ETHEREUM_SEPOLIA_CHAIN_SELECTOR"));
        require(
            localToken.code.length > 0 && localPool.code.length > 0 && remoteToken != address(0)
                && remotePool != address(0),
            "POOL_CONFIG"
        );
        require(address(BurnMintTokenPool(localPool).getToken()) == localToken, "POOL_TOKEN");
        bytes[] memory remotePools = new bytes[](1);
        remotePools[0] = abi.encode(remotePool);
        RateLimiter.Config memory limits = RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0});
        TokenPool.ChainUpdate[] memory additions = new TokenPool.ChainUpdate[](1);
        additions[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteSelector,
            remotePoolAddresses: remotePools,
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: limits,
            inboundRateLimiterConfig: limits
        });
        vm.startBroadcast(key);
        BurnMintTokenPool(localPool).applyChainUpdates(new uint64[](0), additions);
        vm.stopBroadcast();
    }
}
