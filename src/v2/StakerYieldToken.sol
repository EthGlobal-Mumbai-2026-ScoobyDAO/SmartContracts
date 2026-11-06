// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20, SafeToken, Guard} from "../Utils.sol";

/// @notice Fungible claim on yield earned after each unit is minted.
contract StakerYieldToken is Guard {
    using SafeToken for IERC20;

    string public constant name = "RiskFi Staker Yield";
    string public constant symbol = "RF-YT2";
    uint8 public constant decimals = 6;
    uint256 public totalSupply;
    uint256 public globalIndex;
    uint256 public indexRemainder;
    uint256 public yieldFunded;
    uint256 public yieldClaimed;
    bool public matured;
    address public immutable vault;
    IERC20 public immutable usdc;
    uint64 public immutable maturity;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public paidIndex;
    mapping(address => uint256) public unclaimedUSDC;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event YieldNotified(uint256 amount, uint256 index);

    constructor(IERC20 usdc_, address vault_, uint64 maturity_) {
        require(address(usdc_) != address(0) && vault_ != address(0) && maturity_ > block.timestamp, "CONFIG");
        usdc = usdc_;
        vault = vault_;
        maturity = maturity_;
    }

    function _checkpoint(address account) internal {
        if (account == address(0)) return;
        uint256 delta = globalIndex - paidIndex[account];
        if (delta != 0) unclaimedUSDC[account] += balanceOf[account] * delta / 1e18;
        paidIndex[account] = globalIndex;
    }

    function checkpoint(address account) external {
        _checkpoint(account);
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == vault && !matured && to != address(0) && amount > 0, "MINT");
        _checkpoint(to);
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function notifyYield(uint256 amount) external {
        require(msg.sender == vault && !matured && block.timestamp < maturity && totalSupply > 0 && amount > 0, "YIELD");
        require(usdc.balanceOf(address(this)) >= yieldFunded - yieldClaimed + amount, "UNBACKED");
        yieldFunded += amount;
        uint256 scaled = amount * 1e18 + indexRemainder;
        globalIndex += scaled / totalSupply;
        indexRemainder = scaled % totalSupply;
        emit YieldNotified(amount, globalIndex);
    }

    function mature() external {
        require(msg.sender == vault && block.timestamp >= maturity, "MATURITY");
        matured = true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "TO");
        _checkpoint(from);
        _checkpoint(to);
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    function claimYield() external nonReentrant returns (uint256 amount) {
        _checkpoint(msg.sender);
        amount = unclaimedUSDC[msg.sender];
        unclaimedUSDC[msg.sender] = 0;
        yieldClaimed += amount;
        if (amount != 0) usdc.safeTransfer(msg.sender, amount);
    }
}
