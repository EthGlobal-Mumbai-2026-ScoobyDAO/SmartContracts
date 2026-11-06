// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "../Utils.sol";
import {StakerYieldToken} from "./StakerYieldToken.sol";
import {YieldCurveHookV2} from "./YieldCurveHookV2.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

/// @notice View-only CREATE2 salt search for the deployed YieldCurveFactoryV2.
contract V2HookSaltFinder {
    function find(
        address factory,
        IPoolManager manager,
        IERC20 usd,
        StakerYieldToken yt,
        uint64 maturity,
        uint256 start,
        uint256 attempts
    ) external pure returns (bytes32 salt, address predicted, bool found) {
        require(attempts > 0 && attempts <= 50_000, "ATTEMPTS");
        bytes32 initHash = keccak256(
            abi.encodePacked(
                type(YieldCurveHookV2).creationCode,
                abi.encode(
                    manager, usd, yt, maturity, uint24(3000), uint256(1e17), uint256(5e6), uint256(5e16), uint256(2e17)
                )
            )
        );
        uint160 flags = Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;
        for (uint256 i; i < attempts; ++i) {
            salt = bytes32(start + i);
            predicted = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), factory, salt, initHash)))));
            if ((uint160(predicted) & Hooks.ALL_HOOK_MASK) == flags) return (salt, predicted, true);
        }
        return (bytes32(0), address(0), false);
    }
}
