// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Guard} from "../Utils.sol";

interface ILPYieldCheckpoint {
    function beforeShareTransfer(address from, address to) external;
}

contract YieldLPShare is Guard {
    string public constant name = "RiskFi Yield LP Share";
    string public constant symbol = "RF-YLP";
    uint8 public constant decimals = 6;
    address public immutable hook;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(address hook_) {
        hook = hook_;
    }

    function mint(address to, uint256 amount) external nonReentrant {
        require(msg.sender == hook && to != address(0) && amount > 0, "HOOK");
        ILPYieldCheckpoint(hook).beforeShareTransfer(address(0), to);
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external nonReentrant {
        require(msg.sender == hook && amount > 0, "HOOK");
        ILPYieldCheckpoint(hook).beforeShareTransfer(from, address(0));
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external nonReentrant returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external nonReentrant returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "TO");
        ILPYieldCheckpoint(hook).beforeShareTransfer(from, to);
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
