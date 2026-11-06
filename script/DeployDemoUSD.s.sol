// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Script, console2} from "forge-std/Script.sol";
import {DemoUSD} from "../src/DemoUSD.sol";
import {BurnMintTokenPool} from "chainlink-ccip/pools/BurnMintTokenPool.sol";
import {IBurnMintERC20} from "chainlink-ccip/interfaces/IBurnMintERC20.sol";
import {RegistryModuleOwnerCustom} from "chainlink-ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {ITokenAdminRegistry} from "chainlink-ccip/interfaces/ITokenAdminRegistry.sol";

contract DeployDemoUSD is Script {
    function run() external {
        require(block.chainid == 11155111 || block.chainid == 421614, "TESTNET_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(key);
        bool ethereum = block.chainid == 11155111;
        address router = vm.envAddress(ethereum ? "SEPOLIA_CCIP_ROUTER" : "ARBITRUM_SEPOLIA_CCIP_ROUTER");
        address rmn = vm.envAddress(ethereum ? "SEPOLIA_RMN_PROXY" : "ARBITRUM_RMN_PROXY");
        address registry = vm.envAddress(ethereum ? "SEPOLIA_TOKEN_ADMIN_REGISTRY" : "ARBITRUM_TOKEN_ADMIN_REGISTRY");
        address registryModule = vm.envAddress(ethereum ? "SEPOLIA_REGISTRY_MODULE" : "ARBITRUM_REGISTRY_MODULE");
        require(
            router.code.length > 0 && rmn.code.length > 0 && registry.code.length > 0 && registryModule.code.length > 0,
            "CCIP_CONFIG"
        );
        vm.startBroadcast(key);
        DemoUSD token = new DemoUSD();
        BurnMintTokenPool pool = new BurnMintTokenPool(IBurnMintERC20(address(token)), 6, address(0), rmn, router);
        token.grantMintAndBurnRoles(deployer);
        token.grantMintAndBurnRoles(address(pool));
        token.mint(deployer, 1_000_000 * 1e6);
        RegistryModuleOwnerCustom(registryModule).registerAdminViaGetCCIPAdmin(address(token));
        ITokenAdminRegistry(registry).acceptAdminRole(address(token));
        vm.stopBroadcast();
        console2.log("DemoUSD", address(token));
        console2.log("BurnMintTokenPool", address(pool));
    }
}
