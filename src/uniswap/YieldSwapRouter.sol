// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {IERC20, SafeToken, Guard} from "../Utils.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

// Compatible v4 exact-input router for the hook-owned market. It prepays the
// input inside the unlock so the hook can take physical ERC-20 inventory in
// beforeSwap. Standard routers that swap before settling cannot use this hook.
contract YieldSwapRouter is IUnlockCallback, Guard {
    using SafeToken for IERC20;
    using BalanceDeltaLibrary for BalanceDelta;
    IPoolManager public immutable manager;

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    struct SwapCall {
        address payer;
        PoolKey key;
        SwapParams params;
        bytes hookData;
        uint256 minOut;
    }

    function swapExactInput(PoolKey calldata key, bool zeroForOne, uint256 amountIn, uint256 minOut, uint64 deadline)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        require(block.timestamp <= deadline && amountIn > 0 && amountIn <= uint256(uint128(type(int128).max)), "INPUT");
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        SwapCall memory callData = SwapCall(msg.sender, key, params, abi.encode(minOut, deadline), minOut);
        amountOut = abi.decode(manager.unlock(abi.encode(callData)), (uint256));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager), "MANAGER");
        SwapCall memory data = abi.decode(rawData, (SwapCall));
        Currency input = data.params.zeroForOne ? data.key.currency0 : data.key.currency1;
        Currency output = data.params.zeroForOne ? data.key.currency1 : data.key.currency0;
        uint256 amountIn = uint256(-data.params.amountSpecified);
        manager.sync(input);
        IERC20(Currency.unwrap(input)).safeTransferFrom(data.payer, address(manager), amountIn);
        require(manager.settle() == amountIn, "INPUT_DELTA");
        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);
        int128 outDelta = data.params.zeroForOne ? delta.amount1() : delta.amount0();
        require(outDelta > 0 && uint256(uint128(outDelta)) >= data.minOut, "OUTPUT_DELTA");
        uint256 amountOut = uint256(uint128(outDelta));
        manager.take(output, data.payer, amountOut);
        return abi.encode(amountOut);
    }
}
