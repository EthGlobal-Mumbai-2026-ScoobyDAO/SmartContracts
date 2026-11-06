// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IMintableDemoUSD {
    function mint(address account, uint256 amount) external;
}

/// @notice Anyone can claim test dUSD on either Sepolia network after the token admin grants MINTER_ROLE.
/// @dev Each deployment uses the already deployed DemoUSD address for its own chain.
contract PublicDemoUSDFaucet {
    IMintableDemoUSD public immutable token;
    uint256 public immutable amountPerClaim;
    uint64 public immutable cooldownSeconds;
    mapping(address => uint64) public lastClaimAt;

    event Claimed(address indexed account, uint256 amount);

    constructor(IMintableDemoUSD token_, uint256 amountPerClaim_, uint64 cooldownSeconds_) {
        require(address(token_).code.length > 0 && amountPerClaim_ > 0 && cooldownSeconds_ > 0, "CONFIG");
        token = token_;
        amountPerClaim = amountPerClaim_;
        cooldownSeconds = cooldownSeconds_;
    }

    function nextClaimAt(address account) external view returns (uint256) {
        uint64 last = lastClaimAt[account];
        return last == 0 ? 0 : uint256(last) + cooldownSeconds;
    }

    function claim() external {
        uint64 last = lastClaimAt[msg.sender];
        require(last == 0 || block.timestamp >= uint256(last) + cooldownSeconds, "COOLDOWN");
        lastClaimAt[msg.sender] = uint64(block.timestamp);
        token.mint(msg.sender, amountPerClaim);
        emit Claimed(msg.sender, amountPerClaim);
    }
}
