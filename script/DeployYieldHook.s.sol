// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "../src/Utils.sol";
import {YieldSplitter} from "../src/yield/YieldSplitter.sol";
import {YieldToken} from "../src/yield/YieldToken.sol";
import {YieldMarketHook} from "../src/uniswap/YieldMarketHook.sol";
import {YieldHookFactory} from "../src/uniswap/YieldHookFactory.sol";
import {YieldSwapRouter} from "../src/uniswap/YieldSwapRouter.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract DeployYieldHook is Script {
    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        YieldHookFactory factory = YieldHookFactory(vm.envAddress("SEPOLIA_HOOK_FACTORY"));
        YieldSplitter splitter = YieldSplitter(vm.envAddress("SEPOLIA_SPLITTER"));
        uint256 reportId = vm.envUint("REPORT_ID");
        YieldToken yt = splitter.yieldToken(reportId);
        require(address(yt).code.length > 0, "YT_NOT_ISSUED");
        uint64 maturity = uint64(splitter.registry().maturity(reportId));
        require(block.timestamp < maturity, "MATURED");
        IERC20 usdc = splitter.usdc();
        IPoolManager manager = IPoolManager(vm.envAddress("SEPOLIA_V4_POOL_MANAGER"));
        uint24 feePips = uint24(vm.envUint("HOOK_FEE_PIPS"));
        bytes memory initCode =
            abi.encodePacked(type(YieldMarketHook).creationCode, abi.encode(manager, usdc, yt, maturity, feePips));
        bytes32 initCodeHash = keccak256(initCode);
        bytes32 salt;
        address predicted;
        bool found;
        for (uint256 i; i < 200_000; ++i) {
            salt = bytes32(i);
            predicted = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, initCodeHash))))
            );
            if (
                (uint160(predicted) & Hooks.ALL_HOOK_MASK)
                    == (Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG)
            ) {
                found = true;
                break;
            }
        }
        require(found, "NO_PERMISSION_SALT");
        console2.log("Mined hook address", predicted);
        vm.startBroadcast(key);
        YieldMarketHook hook = factory.deployAndInitialize(manager, usdc, yt, maturity, feePips, salt);
        YieldSwapRouter router = new YieldSwapRouter(manager);
        vm.stopBroadcast();
        require(address(hook) == predicted, "ADDRESS_MISMATCH");
        console2.log("YieldMarketHook", address(hook));
        console2.log("YieldLPShare", address(hook.shares()));
        console2.log("YieldSwapRouter", address(router));
    }
}
