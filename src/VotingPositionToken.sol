// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract VotingPositionToken {
    address public immutable owner;
    address public market;
    address public settlement;
    mapping(uint256 => mapping(address => uint256)) public balanceOf;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 amount);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    constructor() { owner = msg.sender; }
    function configure(address market_, address settlement_) external {
        require(msg.sender == owner && market == address(0) && settlement == address(0), "CONFIGURED");
        require(market_ != address(0) && settlement_ != address(0), "ADDRESS");
        market = market_;
        settlement = settlement_;
    }
    function tokenId(uint256 reportId, bool yes) public pure returns (uint256) { return reportId * 2 + (yes ? 1 : 0); }
    function mint(address to, uint256 id, uint256 amount) external {
        require(msg.sender == market && to != address(0) && amount != 0, "MINT");
        balanceOf[id][to] += amount;
        emit TransferSingle(msg.sender, address(0), to, id, amount);
    }
    function burn(address from, uint256 id, uint256 amount) external {
        require(msg.sender == settlement && amount != 0, "BURN");
        balanceOf[id][from] -= amount;
        emit TransferSingle(msg.sender, from, address(0), id, amount);
    }
    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external {
        require(msg.sender == from || isApprovedForAll[from][msg.sender], "APPROVAL");
        require(to != address(0), "TO");
        balanceOf[id][from] -= amount;
        balanceOf[id][to] += amount;
        emit TransferSingle(msg.sender, from, to, id, amount);
        if (to.code.length != 0) {
            (bool ok, bytes memory ret) = to.call(abi.encodeWithSignature("onERC1155Received(address,address,uint256,uint256,bytes)", msg.sender, from, id, amount, data));
            require(ok && ret.length >= 32 && abi.decode(ret, (bytes4)) == 0xf23a6e61, "RECEIVER");
        }
    }
}
