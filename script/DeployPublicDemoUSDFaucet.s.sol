// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {DemoUSD} from "../src/DemoUSD.sol";
import {IMintableDemoUSD, PublicDemoUSDFaucet} from "../src/v2/PublicDemoUSDFaucet.sol";

/// @notice Same script on Ethereum Sepolia and Arbitrum Sepolia; grants only MINTER_ROLE.
contract DeployPublicDemoUSDFaucet is Script {
    function run() external {
        require(block.chainid == 11155111 || block.chainid == 421614, "TESTNET_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(key);
        DemoUSD token = DemoUSD(vm.envAddress(block.chainid == 11155111 ? "SEPOLIA_DEMO_USD" : "ARBITRUM_DEMO_USD"));
        require(address(token).code.length > 0 && token.hasRole(token.DEFAULT_ADMIN_ROLE(), deployer), "TOKEN_ADMIN");
        uint256 amount = vm.envOr("FAUCET_AMOUNT_PER_CLAIM", uint256(100_000_000));
        uint64 cooldown = uint64(vm.envOr("FAUCET_COOLDOWN_SECONDS", uint256(60)));
        vm.startBroadcast(key);
        PublicDemoUSDFaucet faucet = new PublicDemoUSDFaucet(IMintableDemoUSD(address(token)), amount, cooldown);
        token.grantRole(token.MINTER_ROLE(), address(faucet));
        vm.stopBroadcast();
        console2.log("PublicDemoUSDFaucet", address(faucet));
        console2.log("DemoUSD", address(token));
        console2.log("AmountPerClaim", amount);
        console2.log("CooldownSeconds", cooldown);
    }
}
