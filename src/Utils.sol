// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
}

library SafeToken {
    error TokenCallFailed();
    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = address(token).call(abi.encodeCall(IERC20.transfer, (to, amount)));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenCallFailed();
    }
    function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = address(token).call(abi.encodeCall(IERC20.transferFrom, (from, to, amount)));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenCallFailed();
    }
    function safeApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = address(token).call(abi.encodeCall(IERC20.approve, (spender, amount)));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenCallFailed();
    }
}

abstract contract Guard {
    uint256 private entered;
    modifier nonReentrant() {
        require(entered == 0, "REENTRANT");
        entered = 1;
        _;
        entered = 0;
    }
}

library Sig {
    // secp256k1 half-order rejects malleable signatures.
    uint256 private constant HALF_N = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;
    function recover(bytes32 digest, bytes memory signature) internal pure returns (address signer) {
        require(signature.length == 65, "SIG_LENGTH");
        bytes32 r; bytes32 s; uint8 v;
        assembly { r := mload(add(signature, 32)) s := mload(add(signature, 64)) v := byte(0, mload(add(signature, 96))) }
        require(uint256(s) <= HALF_N && (v == 27 || v == 28), "BAD_SIG");
        signer = ecrecover(digest, v, r, s);
        require(signer != address(0), "BAD_SIG");
    }
    function ethSigned(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }
}
