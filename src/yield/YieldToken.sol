// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IERC20, SafeToken, Guard} from "../Utils.sol";

// One ERC-20 YT series per report, issued only at lock. USDC index uses 1e18
// scaling; every balance change checkpoints both sides before the transfer.
contract YieldToken is Guard {
    using SafeToken for IERC20;
    string public name;
    string public symbol;
    uint8 public constant decimals = 6;
    uint256 public totalSupply;
    uint256 public globalIndex;
    uint256 public undistributedDust;
    bool public matured;
    address public immutable splitter;
    IERC20 public immutable usdc;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public paidIndex;
    mapping(address => uint256) public unclaimedUSDC;
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event YieldNotified(uint256 amount, uint256 index);

    constructor(IERC20 usdc_, address splitter_, string memory name_, string memory symbol_) {
        usdc = usdc_;
        splitter = splitter_;
        name = name_;
        symbol = symbol_;
    }

    function _checkpoint(address account) internal {
        if (account == address(0)) return;
        uint256 delta = globalIndex - paidIndex[account];
        if (delta > 0) unclaimedUSDC[account] += balanceOf[account] * delta / 1e18;
        paidIndex[account] = globalIndex;
    }

    function checkpoint(address account) external {
        _checkpoint(account);
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == splitter && totalSupply == 0 && to != address(0) && amount > 0, "MINT");
        _checkpoint(to);
        totalSupply = amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function notifyYield(uint256 amount) external {
        require(msg.sender == splitter && !matured && totalSupply > 0 && amount > 0, "NOTIFY");
        // The splitter transfers backing USDC before notifying.
        require(usdc.balanceOf(address(this)) >= amount, "UNBACKED");
        uint256 scaled = amount * 1e18 + undistributedDust;
        uint256 increment = scaled / totalSupply;
        undistributedDust = scaled % totalSupply;
        globalIndex += increment;
        emit YieldNotified(amount, globalIndex);
    }

    function mature() external {
        require(msg.sender == splitter, "SPLITTER");
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
        if (amount > 0) usdc.safeTransfer(msg.sender, amount);
    }
}
