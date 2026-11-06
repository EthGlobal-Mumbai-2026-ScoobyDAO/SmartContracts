// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice REP: 1:1 receipt for collateral deposited in RiskFiStakeVaultV2 and not yet staked.
/// Only the vault mints (deposit) and burns (stake or withdraw), so REP is never a claim on
/// collateral that already backs a verdict position. Transferable so a CCIP adapter can hand an
/// unstakeable delivery to its payer. Not related to the World IDKit badge in `src/Reputation.sol`.
contract StakeReceiptREP {
    string public constant name = "RiskFi Stake Receipt";
    string public constant symbol = "REP";
    uint8 public constant decimals = 6;
    address public immutable vault;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(address vault_) {
        require(vault_ != address(0), "VAULT");
        vault = vault_;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == vault && to != address(0) && amount > 0, "MINT");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == vault && amount > 0, "BURN");
        require(balanceOf[from] >= amount, "REP_BALANCE");
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
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
        require(balanceOf[from] >= amount, "REP_BALANCE");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
