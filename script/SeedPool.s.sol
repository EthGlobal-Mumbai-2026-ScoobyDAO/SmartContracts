// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Script} from "forge-std/Script.sol";
import {IERC20} from "../src/Utils.sol";
import {Treasury} from "../src/Treasury.sol";
import {YieldMarketHook} from "../src/uniswap/YieldMarketHook.sol";

contract SeedPool is Script {
    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Treasury treasury = Treasury(vm.envAddress("SEPOLIA_TREASURY"));
        YieldMarketHook hook = YieldMarketHook(vm.envAddress("SEPOLIA_HOOK"));
        uint256 usdcAmount = vm.envUint("LIQUIDITY_USD_AMOUNT");
        uint256 ytAmount = vm.envUint("LIQUIDITY_YT_AMOUNT");
        uint256 minShares = vm.envUint("MIN_LP_SHARES");
        require(address(treasury.usdc()) == address(hook.usdc()), "ASSET_MISMATCH");
        vm.startBroadcast(key);
        IERC20 asset = treasury.usdc();
        asset.approve(address(treasury), usdcAmount);
        treasury.fundLiquidity(usdcAmount);
        treasury.seedLiquidity(hook, usdcAmount, ytAmount, minShares);
        vm.stopBroadcast();
    }
}
