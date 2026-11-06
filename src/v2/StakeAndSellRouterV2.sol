// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20, SafeToken, Guard} from "../Utils.sol";
import {RiskFiStakeVaultV2} from "./RiskFiStakeVaultV2.sol";
import {StakerYieldToken} from "./StakerYieldToken.sol";
import {YieldCurveHookV2} from "./YieldCurveHookV2.sol";
import {YieldSwapRouter} from "../uniswap/YieldSwapRouter.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @notice One transaction: deposit collateral, retain verdict position, sell newly minted YT.
contract StakeAndSellRouterV2 is Guard {
    using SafeToken for IERC20;
    RiskFiStakeVaultV2 public immutable vault;
    StakerYieldToken public immutable yt;
    YieldCurveHookV2 public immutable hook;
    YieldSwapRouter public immutable swapRouter;
    IERC20 public immutable usdc;
    PoolKey internal key;
    bool public immutable ytIsCurrency0;

    event StakedAndSold(address indexed staker, bool indexed yes, uint256 staked, uint256 usdcReceived);

    constructor(RiskFiStakeVaultV2 vault_, YieldCurveHookV2 hook_, YieldSwapRouter swapRouter_, PoolKey memory key_) {
        require(
            address(vault_) != address(0) && address(hook_) != address(0) && address(swapRouter_) != address(0),
            "ADDRESS"
        );
        StakerYieldToken yt_ = vault_.yt();
        require(address(yt_) != address(0) && address(hook_.yt()) == address(yt_), "YT");
        require(address(hook_.usdc()) == address(vault_.usdc()), "ASSET");
        require(address(swapRouter_.manager()) == address(hook_.manager()), "MANAGER");
        require(hook_.poolKeyHash() == keccak256(abi.encode(key_)), "POOL_KEY");
        vault = vault_;
        yt = yt_;
        hook = hook_;
        swapRouter = swapRouter_;
        usdc = vault_.usdc();
        key = key_;
        ytIsCurrency0 = Currency.unwrap(key_.currency0) == address(yt_);
    }

    function quoteSell(uint256 ytAmount) external view returns (uint256) {
        return hook.quoteSell(ytAmount);
    }

    function stakeAndSellYield(bool yes, uint256 amount, uint256 minUsdcOut, uint64 deadline)
        external
        nonReentrant
        returns (uint256 usdcOut)
    {
        require(block.timestamp <= deadline && amount > 0, "INPUT");
        uint256 beforeBalance = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        require(usdc.balanceOf(address(this)) - beforeBalance == amount, "TOKEN_DELTA");
        usdc.safeApprove(address(vault), 0);
        usdc.safeApprove(address(vault), amount);
        vault.stake(vault.reportId(), yes, amount, msg.sender, address(this));
        require(yt.approve(address(swapRouter), amount), "YT_APPROVE");
        usdcOut = swapRouter.swapExactInput(key, ytIsCurrency0, amount, minUsdcOut, deadline);
        usdc.safeTransfer(msg.sender, usdcOut);
        emit StakedAndSold(msg.sender, yes, amount, usdcOut);
    }
}
