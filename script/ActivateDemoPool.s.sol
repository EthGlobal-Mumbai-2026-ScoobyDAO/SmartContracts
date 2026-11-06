// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Script} from "forge-std/Script.sol";
import {BurnMintTokenPool} from "chainlink-ccip/pools/BurnMintTokenPool.sol";
import {ITokenAdminRegistry} from "chainlink-ccip/interfaces/ITokenAdminRegistry.sol";

contract ActivateDemoPool is Script {
    function run() external {
        require(block.chainid == 11155111 || block.chainid == 421614, "TESTNET_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        bool ethereum = block.chainid == 11155111;
        address localToken = vm.envAddress(ethereum ? "SEPOLIA_DEMO_USD" : "ARBITRUM_DEMO_USD");
        address localPool = vm.envAddress(ethereum ? "SEPOLIA_DEMO_POOL" : "ARBITRUM_DEMO_POOL");
        address registry = vm.envAddress(ethereum ? "SEPOLIA_TOKEN_ADMIN_REGISTRY" : "ARBITRUM_TOKEN_ADMIN_REGISTRY");
        uint64 remoteSelector =
            uint64(vm.envUint(ethereum ? "ARBITRUM_SEPOLIA_CHAIN_SELECTOR" : "ETHEREUM_SEPOLIA_CHAIN_SELECTOR"));
        require(localToken.code.length > 0 && localPool.code.length > 0 && registry.code.length > 0, "CONFIG");
        require(BurnMintTokenPool(localPool).isSupportedChain(remoteSelector), "REMOTE_POOL_NOT_CONFIGURED");
        vm.startBroadcast(key);
        ITokenAdminRegistry(registry).setPool(localToken, localPool);
        vm.stopBroadcast();
    }
}
