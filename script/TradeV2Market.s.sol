// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "../src/Utils.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";
import {StakerYieldToken} from "../src/v2/StakerYieldToken.sol";
import {YieldCurveHookV2} from "../src/v2/YieldCurveHookV2.sol";
import {StakeAndSellRouterV2} from "../src/v2/StakeAndSellRouterV2.sol";
import {YieldSwapRouter} from "../src/uniswap/YieldSwapRouter.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract TradeV2Market is Script {
    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        uint256 signer = vm.envUint("DEPLOYER_PRIVATE_KEY");
        RiskFiStakeVaultV2 vault = RiskFiStakeVaultV2(vm.envAddress("SEPOLIA_V2_VAULT"));
        YieldCurveHookV2 hook = YieldCurveHookV2(vm.envAddress("SEPOLIA_V2_HOOK"));
        YieldSwapRouter router = YieldSwapRouter(vm.envAddress("SEPOLIA_V2_SWAP_ROUTER"));
        StakeAndSellRouterV2 atomic = StakeAndSellRouterV2(vm.envAddress("SEPOLIA_V2_ATOMIC_ROUTER"));
        IERC20 usd = vault.usdc();
        StakerYieldToken yt = vault.yt();
        address c0 = address(usd) < address(yt) ? address(usd) : address(yt);
        address c1 = address(usd) < address(yt) ? address(yt) : address(usd);
        PoolKey memory key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 0, 1, IHooks(address(hook)));
        require(hook.poolKeyHash() == keccak256(abi.encode(key)) && hook.ytReserve() > 0, "POOL");
        uint64 deadline = uint64(block.timestamp + 1 hours);
        uint256 quoteBuy = hook.quoteBuy(100_000);
        uint256 minBuy = quoteBuy * 95 / 100;
        vm.startBroadcast(signer);
        usd.approve(address(router), 100_000);
        uint256 bought = router.swapExactInput(key, c0 == address(usd), 100_000, minBuy, deadline);
        yt.approve(address(router), bought);
        uint256 quoteSell = hook.quoteSell(bought);
        uint256 minSell = quoteSell * 95 / 100;
        uint256 sold = router.swapExactInput(key, c0 == address(yt), bought, minSell, deadline);
        usd.approve(address(atomic), 10_000_000);
        uint256 atomicQuote = atomic.quoteSell(10_000_000);
        uint256 minAtomic = atomicQuote * 95 / 100;
        uint256 atomicOut = atomic.stakeAndSellYield(false, 10_000_000, minAtomic, deadline);
        vm.stopBroadcast();
        require(bought >= minBuy && sold >= minSell && atomicOut >= minAtomic, "MIN_OUT");
        console2.log("YTBought", bought);
        console2.log("USDSoldBack", sold);
        console2.log("AtomicUSDOut", atomicOut);
    }
}
