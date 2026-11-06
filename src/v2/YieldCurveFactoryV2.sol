// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "../Utils.sol";
import {StakerYieldToken} from "./StakerYieldToken.sol";
import {YieldCurveHookV2} from "./YieldCurveHookV2.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract YieldCurveFactoryV2 {
    address public immutable owner;
    event HookDeployed(address indexed hook, address indexed yt, bytes32 salt);

    constructor(address owner_) {
        require(owner_ != address(0), "OWNER");
        owner = owner_;
    }

    function deployAndInitialize(
        IPoolManager manager,
        IERC20 usdc,
        StakerYieldToken yt,
        uint64 maturity,
        uint24 feePips,
        uint256 anchorRateWad,
        uint256 slopeWadPerUnit,
        uint256 minRateWad,
        uint256 maxRateWad,
        bytes32 salt
    ) external returns (YieldCurveHookV2 hook) {
        require(msg.sender == owner, "OWNER");
        hook = new YieldCurveHookV2{salt: salt}(
            manager, usdc, yt, maturity, feePips, anchorRateWad, slopeWadPerUnit, minRateWad, maxRateWad
        );
        require(uint160(address(hook)) & Hooks.ALL_HOOK_MASK == hook.REQUIRED_FLAGS(), "HOOK_FLAGS");
        address c0 = address(usdc) < address(yt) ? address(usdc) : address(yt);
        address c1 = address(usdc) < address(yt) ? address(yt) : address(usdc);
        PoolKey memory key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 0, 1, IHooks(address(hook)));
        hook.configurePool(key);
        manager.initialize(key, 1 << 96);
        emit HookDeployed(address(hook), address(yt), salt);
    }
}
