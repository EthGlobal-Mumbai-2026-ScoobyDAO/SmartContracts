// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {ERC1155} from "@openzeppelin/contracts@4.9.6/token/ERC1155/ERC1155.sol";

contract VotingPositionToken is ERC1155 {
    address public immutable owner;
    address public market;
    address public settlement;

    constructor() ERC1155("") {
        owner = msg.sender;
    }

    function configure(address market_, address settlement_) external {
        require(msg.sender == owner && market == address(0) && settlement == address(0), "CONFIGURED");
        require(market_ != address(0) && settlement_ != address(0), "ADDRESS");
        market = market_;
        settlement = settlement_;
    }

    function tokenId(uint256 reportId, bool yes) public pure returns (uint256) {
        return reportId * 2 + (yes ? 1 : 0);
    }

    function mint(address to, uint256 id, uint256 amount) external {
        require(msg.sender == market && amount != 0, "MINT");
        _mint(to, id, amount, "");
    }

    function burn(address from, uint256 id, uint256 amount) external {
        require(msg.sender == settlement && amount != 0, "BURN");
        _burn(from, id, amount);
    }
}
