// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "../Utils.sol";
import {ReportRegistry} from "../ReportRegistry.sol";
import {RiskFiStakeVaultV2} from "./RiskFiStakeVaultV2.sol";
import {YieldCurveHookV2} from "./YieldCurveHookV2.sol";
import {CCIPStakeReceiverV2} from "./CCIPStakeReceiverV2.sol";
import {StakeAndSellRouterV2} from "./StakeAndSellRouterV2.sol";
import {V2SeriesFactory} from "./V2SeriesFactory.sol";
import {YieldSwapRouter} from "../uniswap/YieldSwapRouter.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @notice Registers an initialized v4 hook for a published series and creates the local router/CCIP receiver.
contract V2PoolCatalog {
    struct Market {
        address vault;
        address yt;
        address rep;
        address hook;
        address lpShare;
        address swapRouter;
        address stakeAndSellRouter;
        address ccipReceiver;
        bytes32 poolKeyHash;
    }
    V2SeriesFactory public immutable seriesFactory;
    IPoolManager public immutable manager;
    IERC20 public immutable usd;
    YieldSwapRouter public immutable swapRouter;
    address public immutable ccipRouter;
    uint64 public immutable arbSelector;
    mapping(bytes32 => Market) private markets;
    event MarketActivated(
        address indexed registry, uint256 indexed reportId, address hook, address receiver, bytes32 poolKeyHash
    );

    constructor(
        V2SeriesFactory seriesFactory_,
        IPoolManager manager_,
        YieldSwapRouter swapRouter_,
        address ccipRouter_,
        uint64 arbSelector_
    ) {
        require(
            address(seriesFactory_) != address(0) && address(manager_) != address(0)
                && address(swapRouter_) != address(0),
            "ADDRESS"
        );
        require(
            ccipRouter_ != address(0) && arbSelector_ != 0 && address(swapRouter_.manager()) == address(manager_),
            "CONFIG"
        );
        seriesFactory = seriesFactory_;
        manager = manager_;
        usd = seriesFactory_.usd();
        swapRouter = swapRouter_;
        ccipRouter = ccipRouter_;
        arbSelector = arbSelector_;
    }

    function getMarket(address registry, uint256 reportId) external view returns (Market memory) {
        return markets[seriesFactory.key(registry, reportId)];
    }

    function activate(address registry, uint256 reportId, YieldCurveHookV2 hook)
        external
        returns (Market memory market)
    {
        require(msg.sender == ReportRegistry(registry).publisher(), "PUBLISHER");
        V2SeriesFactory.Series memory s = seriesFactory.getSeries(registry, reportId);
        bytes32 k = seriesFactory.key(registry, reportId);
        require(s.vault != address(0) && markets[k].hook == address(0), "STATE");
        RiskFiStakeVaultV2 vault = RiskFiStakeVaultV2(s.vault);
        require(block.timestamp < vault.maturity(), "MATURED");
        require(
            address(hook.yt()) == s.yt && address(hook.usdc()) == address(usd)
                && address(hook.manager()) == address(manager),
            "HOOK"
        );
        address c0 = address(usd) < s.yt ? address(usd) : s.yt;
        address c1 = address(usd) < s.yt ? s.yt : address(usd);
        PoolKey memory pool = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 0, 1, IHooks(address(hook)));
        bytes32 keyHash = keccak256(abi.encode(pool));
        require(hook.poolKeyHash() == keyHash, "POOL");
        StakeAndSellRouterV2 atomicRouter = new StakeAndSellRouterV2(vault, hook, swapRouter, pool);
        CCIPStakeReceiverV2 receiver = new CCIPStakeReceiverV2(ccipRouter, arbSelector, usd, vault, msg.sender);
        market = Market(
            s.vault,
            s.yt,
            s.rep,
            address(hook),
            address(hook.shares()),
            address(swapRouter),
            address(atomicRouter),
            address(receiver),
            keyHash
        );
        markets[k] = market;
        emit MarketActivated(registry, reportId, address(hook), address(receiver), keyHash);
    }
}
