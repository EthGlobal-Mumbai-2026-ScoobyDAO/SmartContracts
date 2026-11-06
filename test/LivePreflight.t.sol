// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IRouterClient} from "chainlink-ccip/interfaces/IRouterClient.sol";
import {ITokenAdminRegistry} from "chainlink-ccip/interfaces/ITokenAdminRegistry.sol";
import {BurnMintTokenPool} from "chainlink-ccip/pools/BurnMintTokenPool.sol";

/// @notice Checks the public infrastructure our deployment scripts depend on.
/// Run with `set -a; source .env; set +a; forge test --match-contract LivePreflightTest -vv`.
contract LivePreflightTest is Test {
    function testEthereumSepoliaInfrastructure() public {
        string memory rpc = vm.envOr("ETH_SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        assertEq(block.chainid, 11155111);
        assertGt(vm.envAddress("SEPOLIA_CCIP_ROUTER").code.length, 0, "CCIP router missing");
        assertGt(vm.envAddress("SEPOLIA_RMN_PROXY").code.length, 0, "RMN missing");
        assertGt(vm.envAddress("SEPOLIA_TOKEN_ADMIN_REGISTRY").code.length, 0, "token registry missing");
        assertGt(vm.envAddress("SEPOLIA_REGISTRY_MODULE").code.length, 0, "registry module missing");
        assertGt(vm.envAddress("SEPOLIA_V4_POOL_MANAGER").code.length, 0, "v4 PoolManager missing");
        _assertPool(
            "SEPOLIA_DEMO_USD",
            "SEPOLIA_DEMO_POOL",
            "SEPOLIA_TOKEN_ADMIN_REGISTRY",
            "ARBITRUM_DEMO_USD",
            "ETHEREUM_SEPOLIA_CHAIN_SELECTOR",
            "ARBITRUM_SEPOLIA_CHAIN_SELECTOR"
        );
    }

    function testArbitrumSepoliaCCIPLane() public {
        string memory rpc = vm.envOr("ARB_SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        assertEq(block.chainid, 421614);
        address router = vm.envAddress("ARBITRUM_SEPOLIA_CCIP_ROUTER");
        assertGt(router.code.length, 0, "CCIP router missing");
        assertGt(vm.envAddress("ARBITRUM_RMN_PROXY").code.length, 0, "RMN missing");
        assertGt(vm.envAddress("ARBITRUM_TOKEN_ADMIN_REGISTRY").code.length, 0, "token registry missing");
        assertGt(vm.envAddress("ARBITRUM_REGISTRY_MODULE").code.length, 0, "registry module missing");
        assertTrue(
            IRouterClient(router).isChainSupported(uint64(vm.envUint("ETHEREUM_SEPOLIA_CHAIN_SELECTOR"))),
            "CCIP lane unavailable"
        );
        _assertPool(
            "ARBITRUM_DEMO_USD",
            "ARBITRUM_DEMO_POOL",
            "ARBITRUM_TOKEN_ADMIN_REGISTRY",
            "SEPOLIA_DEMO_USD",
            "ARBITRUM_SEPOLIA_CHAIN_SELECTOR",
            "ETHEREUM_SEPOLIA_CHAIN_SELECTOR"
        );
    }

    function _assertPool(
        string memory tokenKey,
        string memory poolKey,
        string memory registryKey,
        string memory remoteTokenKey,
        string memory localSelectorKey,
        string memory remoteSelectorKey
    ) internal {
        address token = vm.envAddress(tokenKey);
        address pool = vm.envAddress(poolKey);
        uint64 remoteSelector = uint64(vm.envUint(remoteSelectorKey));
        assertGt(token.code.length, 0, "DemoUSD missing");
        assertEq(ITokenAdminRegistry(vm.envAddress(registryKey)).getPool(token), pool, "pool not registered");
        assertEq(address(BurnMintTokenPool(pool).getToken()), token, "wrong pool token");
        assertTrue(BurnMintTokenPool(pool).isSupportedChain(remoteSelector), "remote pool not configured");
        assertEq(
            abi.decode(BurnMintTokenPool(pool).getRemoteToken(remoteSelector), (address)),
            vm.envAddress(remoteTokenKey),
            "wrong remote token"
        );
        assertGt(vm.envUint(localSelectorKey), 0);
    }
}
