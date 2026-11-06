// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IERC20, SafeToken, Guard} from "./Utils.sol";
import {YieldToken} from "./yield/YieldToken.sol";
import {YieldMarketHook} from "./uniswap/YieldMarketHook.sol";
import {YieldLPShare} from "./uniswap/YieldLPShare.sol";

// The LP budget is funded separately from voter principal. Settlement sends
// its 20% losing-pool fee here after finalization; treasury inventory is never
// used by VoteMarket to back VPT redemptions.
contract Treasury is Guard {
    using SafeToken for IERC20;
    address public immutable owner;
    IERC20 public immutable usdc;
    uint256 public unspentLiquidityBudget;
    event LiquidityFunded(address indexed funder, uint256 amount);
    event LiquiditySeeded(address indexed hook, uint256 usdcAmount, uint256 ytAmount, uint256 shares);
    event FreeUSDCWithdrawn(address indexed to, uint256 amount);

    constructor(IERC20 usdc_, address owner_) {
        require(address(usdc_) != address(0) && owner_ != address(0));
        usdc = usdc_;
        owner = owner_;
    }
    modifier onlyOwner() {
        require(msg.sender == owner, "OWNER");
        _;
    }

    function fundLiquidity(uint256 amount) external nonReentrant {
        require(amount > 0, "AMOUNT");
        uint256 beforeBalance = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        require(usdc.balanceOf(address(this)) - beforeBalance == amount, "TOKEN_DELTA");
        unspentLiquidityBudget += amount;
        emit LiquidityFunded(msg.sender, amount);
    }

    function seedLiquidity(YieldMarketHook hook, uint256 usdcAmount, uint256 ytAmount, uint256 minShares)
        external
        onlyOwner
        nonReentrant
        returns (uint256 minted)
    {
        require(address(hook.usdc()) == address(usdc) && usdcAmount <= unspentLiquidityBudget, "BUDGET");
        YieldToken yt = hook.yt();
        unspentLiquidityBudget -= usdcAmount;
        usdc.safeApprove(address(hook), 0);
        usdc.safeApprove(address(hook), usdcAmount);
        require(yt.approve(address(hook), ytAmount), "YT_APPROVE");
        minted = hook.addLiquidity(usdcAmount, ytAmount, minShares);
        emit LiquiditySeeded(address(hook), usdcAmount, ytAmount, minted);
    }

    function removeLiquidity(YieldMarketHook hook, uint256 shares, uint256 minUSDC, uint256 minYT)
        external
        onlyOwner
        nonReentrant
    {
        hook.removeLiquidity(shares, minUSDC, minYT);
    }

    function claimLPYield(YieldMarketHook hook) external onlyOwner nonReentrant returns (uint256) {
        return hook.claimLPYield();
    }

    function claimYT(YieldToken yt) external onlyOwner nonReentrant returns (uint256) {
        return yt.claimYield();
    }

    function withdrawFreeUSDC(address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0) && usdc.balanceOf(address(this)) >= unspentLiquidityBudget + amount, "RESERVED");
        usdc.safeTransfer(to, amount);
        emit FreeUSDCWithdrawn(to, amount);
    }

    function withdrawYT(YieldToken yt, address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0) && yt.transfer(to, amount), "YT_TRANSFER");
    }

    function lpShares(YieldMarketHook hook) external view returns (uint256) {
        YieldLPShare lp = hook.shares();
        return lp.balanceOf(address(this));
    }
}
