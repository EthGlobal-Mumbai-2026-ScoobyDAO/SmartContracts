// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "../src/Utils.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";
import {StakerYieldToken} from "../src/v2/StakerYieldToken.sol";
import {YieldCurveHookV2} from "../src/v2/YieldCurveHookV2.sol";
import {YieldCurveFactoryV2} from "../src/v2/YieldCurveFactoryV2.sol";
import {StakeAndSellRouterV2} from "../src/v2/StakeAndSellRouterV2.sol";
import {YieldSwapRouter} from "../src/uniswap/YieldSwapRouter.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract DeployV2Hook is Script {
    uint24 constant FEE = 3000;
    uint256 constant ANCHOR = 1e17;
    uint256 constant SLOPE = 5e6;
    uint256 constant MIN_RATE = 5e16;
    uint256 constant MAX_RATE = 2e17;

    struct Config {
        YieldCurveFactoryV2 factory;
        RiskFiStakeVaultV2 vault;
        IPoolManager manager;
        IERC20 token;
        StakerYieldToken yt;
        uint64 maturity;
    }

    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        uint256 signer = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Config memory c;
        c.factory = YieldCurveFactoryV2(vm.envAddress("SEPOLIA_V2_HOOK_FACTORY"));
        c.vault = RiskFiStakeVaultV2(vm.envAddress("SEPOLIA_V2_VAULT"));
        c.manager = IPoolManager(vm.envAddress("SEPOLIA_V4_POOL_MANAGER"));
        c.token = c.vault.usdc();
        c.yt = c.vault.yt();
        c.maturity = c.vault.maturity();
        require(
            address(c.factory).code.length > 0 && address(c.manager).code.length > 0 && address(c.yt).code.length > 0,
            "CONTRACTS"
        );
        require(c.factory.owner() == vm.addr(signer) && c.maturity > block.timestamp, "CONFIG");
        bytes32 initHash = keccak256(
            abi.encodePacked(
                type(YieldCurveHookV2).creationCode,
                abi.encode(c.manager, c.token, c.yt, c.maturity, FEE, ANCHOR, SLOPE, MIN_RATE, MAX_RATE)
            )
        );
        (bytes32 salt, address predicted) = _mine(address(c.factory), initHash);
        vm.startBroadcast(signer);
        YieldCurveHookV2 hook = c.factory
            .deployAndInitialize(c.manager, c.token, c.yt, c.maturity, FEE, ANCHOR, SLOPE, MIN_RATE, MAX_RATE, salt);
        YieldSwapRouter swapRouter = new YieldSwapRouter(c.manager);
        address c0 = address(c.token) < address(c.yt) ? address(c.token) : address(c.yt);
        address c1 = address(c.token) < address(c.yt) ? address(c.yt) : address(c.token);
        PoolKey memory key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 0, 1, IHooks(address(hook)));
        StakeAndSellRouterV2 atomicRouter = new StakeAndSellRouterV2(c.vault, hook, swapRouter, key);
        vm.stopBroadcast();
        require(address(hook) == predicted, "ADDRESS_MISMATCH");
        console2.log("V2Hook", address(hook));
        console2.log("V2LPShare", address(hook.shares()));
        console2.log("V2SwapRouter", address(swapRouter));
        console2.log("V2AtomicRouter", address(atomicRouter));
    }

    function _mine(address factory, bytes32 initHash) internal pure returns (bytes32 salt, address predicted) {
        uint160 flags = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;
        for (uint256 i; i < 300_000; ++i) {
            salt = bytes32(i);
            predicted = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), factory, salt, initHash)))));
            if ((uint160(predicted) & Hooks.ALL_HOOK_MASK) == flags) return (salt, predicted);
        }
        revert("NO_PERMISSION_SALT");
    }
}
