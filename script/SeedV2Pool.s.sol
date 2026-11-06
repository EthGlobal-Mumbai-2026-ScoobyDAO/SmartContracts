// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "../src/Utils.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";
import {StakerYieldToken} from "../src/v2/StakerYieldToken.sol";
import {YieldCurveHookV2} from "../src/v2/YieldCurveHookV2.sol";

contract SeedV2Pool is Script {
    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        uint256 signer = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address wallet = vm.addr(signer);
        RiskFiStakeVaultV2 vault = RiskFiStakeVaultV2(vm.envAddress("SEPOLIA_V2_VAULT"));
        YieldCurveHookV2 hook = YieldCurveHookV2(vm.envAddress("SEPOLIA_V2_HOOK"));
        IERC20 usd = vault.usdc();
        StakerYieldToken yt = vault.yt();
        require(vault.reportId() == vm.envUint("V2_REPORT_ID") && hook.yt() == yt, "SERIES");
        require(
            hook.shares().totalSupply() == 0 && block.timestamp < vault.registry().getReport(vault.reportId()).lockTime,
            "START"
        );
        vm.startBroadcast(signer);
        usd.approve(address(vault), 100_000_000);
        vault.stake(vault.reportId(), true, 100_000_000, wallet, wallet);
        usd.approve(address(hook), 50_000_000);
        yt.approve(address(hook), 100_000_000);
        hook.addLiquidity(50_000_000, 100_000_000, 1);
        vm.stopBroadcast();
        console2.log("V2LPShareBalance", hook.shares().balanceOf(wallet));
    }
}
