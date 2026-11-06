// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IERC20, SafeToken, Guard} from "../Utils.sol";

// SIMULATED vault for deterministic Foundry and short demo series. It is not
// an Aave adapter or a promise of positive interest.
contract YieldVaultAdapter is Guard {
    using SafeToken for IERC20;
    IERC20 public immutable asset;
    address public immutable splitter;
    address public immutable admin;
    uint256 public principal;
    event YieldInjected(uint256 amount);
    event SimulatedLoss(uint256 amount);
    constructor(IERC20 asset_, address splitter_, address admin_) {
        require(address(asset_) != address(0) && splitter_ != address(0) && admin_ != address(0));
        asset = asset_; splitter = splitter_; admin = admin_;
    }
    function totalAssets() public view returns (uint256) { return asset.balanceOf(address(this)); }
    function positiveYield() external view returns (uint256) { uint256 a = totalAssets(); return a > principal ? a - principal : 0; }
    function deposit(uint256 amount) external nonReentrant {
        require(msg.sender == splitter && amount > 0, "SPLITTER");
        uint256 beforeBalance = totalAssets();
        asset.safeTransferFrom(msg.sender, address(this), amount);
        require(totalAssets() - beforeBalance == amount, "TOKEN_DELTA");
        principal += amount;
    }
    function withdraw(address to, uint256 amount, bool principalWithdrawal) external nonReentrant {
        require(msg.sender == splitter && to != address(0), "SPLITTER");
        if (principalWithdrawal) principal -= amount;
        else require(totalAssets() >= principal + amount, "NO_YIELD");
        asset.safeTransfer(to, amount);
    }
    function closePrincipal(uint256 notional) external { require(msg.sender == splitter, "SPLITTER"); principal -= notional; }
    function injectYield(uint256 amount) external nonReentrant {
        uint256 beforeBalance = totalAssets();
        asset.safeTransferFrom(msg.sender, address(this), amount);
        require(totalAssets() - beforeBalance == amount, "TOKEN_DELTA");
        emit YieldInjected(amount);
    }
    function simulateLoss(address sink, uint256 amount) external nonReentrant {
        require(msg.sender == admin && sink != address(0), "ADMIN");
        asset.safeTransfer(sink, amount);
        emit SimulatedLoss(amount);
    }
}
