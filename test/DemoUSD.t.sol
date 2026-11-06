// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {DemoUSD} from "../src/DemoUSD.sol";
import {BurnMintTokenPool} from "chainlink-ccip/pools/BurnMintTokenPool.sol";
import {IBurnMintERC20} from "chainlink-ccip/interfaces/IBurnMintERC20.sol";
import {TokenPool} from "chainlink-ccip/pools/TokenPool.sol";
import {RateLimiter} from "chainlink-ccip/libraries/RateLimiter.sol";
import {TokenAdminRegistry} from "chainlink-ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RegistryModuleOwnerCustom} from "chainlink-ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";

contract DemoUSDTest is Test {
    function testOfficialChainlinkTokenPoolRegistration() public {
        DemoUSD token = new DemoUSD();
        assertEq(token.decimals(), 6);
        assertEq(token.symbol(), "dUSD");
        vm.expectRevert();
        token.mint(address(this), 1_000_000);
        BurnMintTokenPool pool =
            new BurnMintTokenPool(IBurnMintERC20(address(token)), 6, address(0), address(0xAAA), address(0xBBB));
        token.grantMintAndBurnRoles(address(pool));
        token.grantMintAndBurnRoles(address(this));
        token.mint(address(this), 1_000_000);
        assertEq(token.balanceOf(address(this)), 1_000_000);
        TokenAdminRegistry registry = new TokenAdminRegistry();
        RegistryModuleOwnerCustom module = new RegistryModuleOwnerCustom(address(registry));
        registry.addRegistryModule(address(module));
        module.registerAdminViaGetCCIPAdmin(address(token));
        registry.acceptAdminRole(address(token));
        uint64 remoteSelector = 16015286601757825753;
        address remoteToken = address(0x1234);
        address remotePool = address(0x5678);
        bytes[] memory remotePools = new bytes[](1);
        remotePools[0] = abi.encode(remotePool);
        RateLimiter.Config memory limits = RateLimiter.Config(false, 0, 0);
        TokenPool.ChainUpdate[] memory additions = new TokenPool.ChainUpdate[](1);
        additions[0] = TokenPool.ChainUpdate(remoteSelector, remotePools, abi.encode(remoteToken), limits, limits);
        pool.applyChainUpdates(new uint64[](0), additions);
        registry.setPool(address(token), address(pool));
        assertEq(registry.getPool(address(token)), address(pool));
        assertTrue(pool.isSupportedChain(remoteSelector));
        assertEq(abi.decode(pool.getRemoteToken(remoteSelector), (address)), remoteToken);
    }
}
