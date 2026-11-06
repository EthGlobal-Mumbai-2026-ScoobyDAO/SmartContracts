// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {V2MockUSD} from "./helpers/V2Mocks.sol";
import {ReportRegistry} from "../src/ReportRegistry.sol";
import {FlexibleReportRegistry} from "../src/v2/FlexibleReportRegistry.sol";
import {V2SeriesFactory} from "../src/v2/V2SeriesFactory.sol";
import {V2PoolCatalog} from "../src/v2/V2PoolCatalog.sol";
import {V2HookSaltFinder} from "../src/v2/V2HookSaltFinder.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";
import {YieldCurveHookV2} from "../src/v2/YieldCurveHookV2.sol";
import {YieldCurveFactoryV2} from "../src/v2/YieldCurveFactoryV2.sol";
import {YieldSwapRouter} from "../src/uniswap/YieldSwapRouter.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract V2MarketSetupTest is Test {
    uint256 constant REVIEWER_KEY = 0xA11CE;
    address constant ALICE = address(0xBEEF);
    V2MockUSD usd;
    FlexibleReportRegistry flexible;
    ReportRegistry original;
    V2SeriesFactory seriesFactory;
    V2PoolCatalog catalog;
    V2HookSaltFinder finder;
    YieldCurveFactoryV2 hookFactory;
    YieldSwapRouter router;
    IPoolManager manager;
    uint64 lockTime;
    uint64 maturity;

    function setUp() public {
        usd = new V2MockUSD();
        flexible = new FlexibleReportRegistry(address(this));
        original = new ReportRegistry(address(this));
        manager = IPoolManager(address(new PoolManager(address(this))));
        router = new YieldSwapRouter(manager);
        hookFactory = new YieldCurveFactoryV2(address(this));
        finder = new V2HookSaltFinder();
        seriesFactory = new V2SeriesFactory(usd, address(original), address(flexible));
        catalog = new V2PoolCatalog(seriesFactory, manager, router, address(0xCC1F), 3478487238524512106);
        lockTime = uint64(block.timestamp + 2 hours);
        maturity = uint64(block.timestamp + 3 hours);
        usd.mint(ALICE, 1_000_000_000);
    }

    function publishFlexible() internal returns (uint256) {
        FlexibleReportRegistry.Report memory r = FlexibleReportRegistry.Report({
            reportHash: keccak256("report"),
            claimHash: keccak256("claim"),
            reviewer: vm.addr(REVIEWER_KEY),
            resolver: address(this),
            adjudicator: address(this),
            lockTime: lockTime,
            crossChainCutoff: uint64(block.timestamp + 1 hours),
            resultDeadline: uint64(block.timestamp + 4 hours),
            challengePeriod: 5 minutes
        });
        uint64 expiry = uint64(block.timestamp + 10 minutes);
        (uint8 v, bytes32 a, bytes32 b) = vm.sign(REVIEWER_KEY, flexible.approvalDigest(r, maturity, 1, expiry));
        return flexible.publish(r, maturity, 1, expiry, abi.encodePacked(a, b, v));
    }

    function testPublishedFlexibleReportCanPrepareActivateStakeAndTrade() public {
        uint256 id = publishFlexible();
        vm.prank(ALICE);
        vm.expectRevert(bytes("PUBLISHER"));
        seriesFactory.prepare(address(flexible), id, address(this));
        (address vaultAddress, address yt) = seriesFactory.prepare(address(flexible), id, address(this));
        assertEq(RiskFiStakeVaultV2(vaultAddress).reportId(), id);
        bytes32 salt;
        bool found;
        for (uint256 start; start < 300_000 && !found; start += 50_000) {
            (salt,, found) = finder.find(
                address(hookFactory), manager, usd, RiskFiStakeVaultV2(vaultAddress).yt(), maturity, start, 50_000
            );
        }
        assertTrue(found);
        YieldCurveHookV2 hook = hookFactory.deployAndInitialize(
            manager, usd, RiskFiStakeVaultV2(vaultAddress).yt(), maturity, 3000, 1e17, 5e6, 5e16, 2e17, salt
        );
        V2PoolCatalog.Market memory market = catalog.activate(address(flexible), id, hook);
        assertEq(market.hook, address(hook));
        assertEq(market.yt, yt);
        assertTrue(market.ccipReceiver != address(0) && market.stakeAndSellRouter != address(0));
        vm.startPrank(ALICE);
        usd.approve(vaultAddress, 400_000_000);
        RiskFiStakeVaultV2(vaultAddress).stake(id, true, 300_000_000, ALICE, ALICE);
        RiskFiStakeVaultV2(vaultAddress).stake(id, false, 100_000_000, ALICE, ALICE);
        usd.approve(address(hook), 50_000_000);
        RiskFiStakeVaultV2(vaultAddress).yt().approve(address(hook), 100_000_000);
        hook.addLiquidity(50_000_000, 100_000_000, 1);
        usd.approve(address(router), 100);
        vm.stopPrank();
        address c0 = address(usd) < yt ? address(usd) : yt;
        address c1 = address(usd) < yt ? yt : address(usd);
        PoolKey memory key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 0, 1, IHooks(address(hook)));
        uint256 quoted = hook.quoteBuy(100);
        vm.prank(ALICE);
        uint256 bought =
            router.swapExactInput(key, address(usd) < yt, 100, quoted * 95 / 100, uint64(block.timestamp + 10 minutes));
        assertEq(bought, quoted);
    }

    function testOriginalRegistryCanPreparePublishedReport() public {
        ReportRegistry.Report memory r = ReportRegistry.Report({
            reportHash: keccak256("old report"),
            claimHash: keccak256("old claim"),
            reviewer: vm.addr(REVIEWER_KEY),
            resolver: address(this),
            adjudicator: address(this),
            lockTime: lockTime,
            crossChainCutoff: uint64(block.timestamp + 1 hours),
            resultDeadline: uint64(uint256(lockTime) + 32 days),
            challengePeriod: 1 hours
        });
        uint64 expiry = uint64(block.timestamp + 10 minutes);
        (uint8 v, bytes32 a, bytes32 b) = vm.sign(REVIEWER_KEY, original.approvalDigest(r, 1, expiry));
        uint256 id = original.publish(r, 1, expiry, abi.encodePacked(a, b, v));
        (address vaultAddress,) = seriesFactory.prepare(address(original), id, address(this));
        assertEq(RiskFiStakeVaultV2(vaultAddress).maturity(), lockTime + 30 days);
    }
}
