// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "../../src/Utils.sol";
import {Client} from "chainlink-ccip/libraries/Client.sol";
import {IRouterClient} from "chainlink-ccip/interfaces/IRouterClient.sol";
import {IAny2EVMMessageReceiver} from "chainlink-ccip/interfaces/IAny2EVMMessageReceiver.sol";

/// @notice Six-decimal demo collateral used only by V2 local tests.
contract V2MockUSD is IERC20 {
    string public constant name = "V2 Mock Dollar";
    string public constant symbol = "v2USD";
    uint8 public constant decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function burn(address from, uint256 amount) external {
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice Local CCIP shape. Optional token pair simulates source burn and destination mint.
contract V2MockCCIPRouter is IRouterClient {
    uint64 public constant SOURCE = 12345;
    uint256 public sequence;
    bool public autoDeliver = true;
    V2MockUSD public sourceToken;
    V2MockUSD public destinationToken;
    mapping(bytes32 => bytes) public pending;

    function setAutoDeliver(bool enabled) external {
        autoDeliver = enabled;
    }

    function setTokenPair(V2MockUSD source_, V2MockUSD destination_) external {
        require(address(sourceToken) == address(0), "PAIR_SET");
        sourceToken = source_;
        destinationToken = destination_;
    }

    function isChainSupported(uint64) external pure returns (bool) {
        return true;
    }

    function getFee(uint64, Client.EVM2AnyMessage memory) external pure returns (uint256) {
        return 0;
    }

    function ccipSend(uint64, Client.EVM2AnyMessage calldata message) external payable returns (bytes32 messageId) {
        messageId = keccak256(abi.encode(++sequence, msg.sender));
        address receiver = abi.decode(message.receiver, (address));
        Client.EVMTokenAmount[] memory tokens = new Client.EVMTokenAmount[](message.tokenAmounts.length);
        for (uint256 i; i < tokens.length; ++i) {
            tokens[i] = message.tokenAmounts[i];
            require(V2MockUSD(tokens[i].token).transferFrom(msg.sender, address(this), tokens[i].amount), "TRANSFER");
        }
        Client.Any2EVMMessage memory delivered =
            Client.Any2EVMMessage(messageId, SOURCE, abi.encode(msg.sender), message.data, tokens);
        pending[messageId] = abi.encode(receiver, delivered);
        if (autoDeliver) deliver(messageId);
    }

    function deliver(bytes32 messageId) public {
        bytes memory payload = pending[messageId];
        require(payload.length != 0, "PENDING");
        delete pending[messageId];
        (address receiver, Client.Any2EVMMessage memory delivered) =
            abi.decode(payload, (address, Client.Any2EVMMessage));
        for (uint256 i; i < delivered.destTokenAmounts.length; ++i) {
            Client.EVMTokenAmount memory token = delivered.destTokenAmounts[i];
            if (address(sourceToken) != address(0)) {
                require(token.token == address(sourceToken), "SOURCE_TOKEN");
                sourceToken.burn(address(this), token.amount);
                destinationToken.mint(receiver, token.amount);
                delivered.destTokenAmounts[i].token = address(destinationToken);
            } else {
                require(V2MockUSD(token.token).transfer(receiver, token.amount), "TRANSFER");
            }
        }
        IAny2EVMMessageReceiver(receiver).ccipReceive(delivered);
    }
}
