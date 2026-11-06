// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Principal accounting is deliberately non-transferable. Settlement escrow is
// the only owner, so voters cannot double redeem the same USDC via PT and VPT.
contract PrincipalToken {
    address public immutable splitter;
    mapping(uint256 => mapping(address => uint256)) public balanceOf;
    event TransferSingle(address indexed from, address indexed to, uint256 indexed id, uint256 amount);
    constructor(address splitter_) { splitter = splitter_; }
    function mint(address to, uint256 id, uint256 amount) external {
        require(msg.sender == splitter && to != address(0), "SPLITTER");
        balanceOf[id][to] += amount;
        emit TransferSingle(address(0), to, id, amount);
    }
    function burn(address from, uint256 id, uint256 amount) external {
        require(msg.sender == splitter, "SPLITTER");
        balanceOf[id][from] -= amount;
        emit TransferSingle(from, address(0), id, amount);
    }
}
