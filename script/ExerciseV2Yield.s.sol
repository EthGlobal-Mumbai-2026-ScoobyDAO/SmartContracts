// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "../src/Utils.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";
import {YieldCurveHookV2} from "../src/v2/YieldCurveHookV2.sol";

/// @notice Injects demo yield and claims it for the LP and YT holder on Ethereum Sepolia.
contract ExerciseV2Yield is Script {
    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        uint256 signer = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address wallet = vm.addr(signer);
        RiskFiStakeVaultV2 vault = RiskFiStakeVaultV2(vm.envAddress("SEPOLIA_V2_VAULT"));
        YieldCurveHookV2 hook = YieldCurveHookV2(vm.envAddress("SEPOLIA_V2_HOOK"));
        require(address(hook.yt()) == address(vault.yt()), "SERIES");
        require(hook.shares().balanceOf(wallet) > 0 && block.timestamp < vault.maturity(), "POSITION");
        uint256 amount = vm.envOr("V2_DEMO_YIELD", uint256(10_000_000));
        require(amount > 0, "YIELD_AMOUNT");
        IERC20 usd = vault.usdc();
        require(usd.balanceOf(wallet) >= amount, "USD_BALANCE");

        vm.startBroadcast(signer);
        usd.approve(address(vault), amount);
        vault.injectYield(amount);
        uint256 lpClaimed = hook.claimLPYield();
        uint256 ytClaimed = vault.yt().claimYield();
        vm.stopBroadcast();

        console2.log("Demo yield injected", amount);
        console2.log("LP yield claimed", lpClaimed);
        console2.log("Wallet YT yield claimed", ytClaimed);
    }
}
