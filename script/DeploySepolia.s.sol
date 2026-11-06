// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "../src/Utils.sol";
import {ReportRegistry} from "../src/ReportRegistry.sol";
import {VotingPositionToken} from "../src/VotingPositionToken.sol";
import {VoteMarket} from "../src/VoteMarket.sol";
import {Settlement} from "../src/Settlement.sol";
import {Reputation} from "../src/Reputation.sol";
import {Treasury} from "../src/Treasury.sol";
import {YieldSplitter} from "../src/yield/YieldSplitter.sol";
import {YieldVaultAdapter} from "../src/yield/YieldVaultAdapter.sol";
import {CCIPStakeReceiver} from "../src/ccip/CCIPStakeReceiver.sol";
import {YieldHookFactory} from "../src/uniswap/YieldHookFactory.sol";

contract DeploySepolia is Script {
    struct Config {
        address deployer;
        IERC20 usdc;
        address router;
        address identitySigner;
        uint64 sourceSelector;
    }

    struct Contracts {
        Treasury treasury;
        ReportRegistry registry;
        VotingPositionToken positions;
        VoteMarket market;
        Settlement settlement;
        YieldSplitter splitter;
        YieldVaultAdapter vault;
        CCIPStakeReceiver receiver;
        Reputation reputation;
        YieldHookFactory hookFactory;
    }

    function run() external {
        require(block.chainid == 11155111, "ETHEREUM_SEPOLIA_ONLY");
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Config memory c = Config({
            deployer: vm.addr(key),
            usdc: IERC20(vm.envAddress("SEPOLIA_DEMO_USD")),
            router: vm.envAddress("SEPOLIA_CCIP_ROUTER"),
            identitySigner: vm.envAddress("IDENTITY_SIGNER"),
            sourceSelector: uint64(vm.envUint("ARBITRUM_SEPOLIA_CHAIN_SELECTOR"))
        });
        require(address(c.usdc).code.length > 0 && c.router.code.length > 0, "PRECHECK_CODE");
        require(vm.envAddress("SEPOLIA_V4_POOL_MANAGER").code.length > 0, "POOL_MANAGER");
        require(c.identitySigner != address(0) && c.sourceSelector != 0, "PRECHECK_CONFIG");
        vm.startBroadcast(key);
        Contracts memory d;
        d.treasury = new Treasury(c.usdc, c.deployer);
        d.registry = new ReportRegistry(c.deployer);
        d.positions = new VotingPositionToken();
        d.market = new VoteMarket(c.usdc, d.registry, d.positions);
        d.settlement = new Settlement(d.registry, d.market, d.positions, address(d.treasury));
        d.splitter =
            new YieldSplitter(c.usdc, d.registry, address(d.market), address(d.settlement), address(d.treasury));
        d.vault = new YieldVaultAdapter(c.usdc, address(d.splitter), c.deployer);
        d.receiver =
            new CCIPStakeReceiver(c.router, c.sourceSelector, address(0), c.usdc, d.market, d.registry, c.deployer);
        d.reputation = new Reputation(d.settlement, c.identitySigner);
        d.hookFactory = new YieldHookFactory(c.deployer);
        d.splitter.configureVault(d.vault);
        d.positions.configure(address(d.market), address(d.settlement));
        d.market.configure(address(d.settlement), address(d.receiver));
        d.market.configureSplitter(d.splitter);
        vm.stopBroadcast();
        console2.log("Treasury", address(d.treasury));
        console2.log("Registry", address(d.registry));
        console2.log("Positions", address(d.positions));
        console2.log("Market", address(d.market));
        console2.log("Settlement", address(d.settlement));
        console2.log("Splitter", address(d.splitter));
        console2.log("MockVault", address(d.vault));
        console2.log("CCIPReceiver", address(d.receiver));
        console2.log("Reputation", address(d.reputation));
        console2.log("HookFactory", address(d.hookFactory));
    }
}
