// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "../src/Utils.sol";
import {V2SeriesFactory} from "../src/v2/V2SeriesFactory.sol";
import {V2PoolCatalog} from "../src/v2/V2PoolCatalog.sol";
import {V2HookSaltFinder} from "../src/v2/V2HookSaltFinder.sol";
import {YieldSwapRouter} from "../src/uniswap/YieldSwapRouter.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

contract DeployV2MarketInfrastructure is Script {
    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        uint256 signer = vm.envUint("DEPLOYER_PRIVATE_KEY");
        IERC20 usd = IERC20(0x3d1F1BFfb82A244Bf58Ff42A3202e7d25AEb2525);
        address original = 0x805d681383f580403B979Bf1D017cff045dC7eBd;
        address flexible = 0xE983eb98B00e9c26179202b69393d97981794447;
        IPoolManager manager = IPoolManager(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543);
        YieldSwapRouter router = YieldSwapRouter(0x2B272b404e82f16ad7AcAdC8fD2c12329876CEC1);
        require(
            address(usd).code.length > 0 && address(manager).code.length > 0 && address(router).code.length > 0,
            "DEPENDENCIES"
        );
        vm.startBroadcast(signer);
        V2SeriesFactory series = new V2SeriesFactory(usd, original, flexible);
        V2PoolCatalog catalog =
            new V2PoolCatalog(series, manager, router, 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59, 3478487238524512106);
        V2HookSaltFinder finder = new V2HookSaltFinder();
        vm.stopBroadcast();
        console2.log("V2SeriesFactory", address(series));
        console2.log("V2PoolCatalog", address(catalog));
        console2.log("V2HookSaltFinder", address(finder));
    }
}
