# Uniswap v4 developer feedback

We are building a yield-token market whose LPs must receive the yield earned while YT sits in market inventory. A standard PoolManager-held YT position does not by itself attribute that ERC-20 accrual to LPs. We therefore tested a hook-owned reserve model with explicit LP shares and a yield index.

The concrete integration issue was swap order. The core `PoolSwapTest` router swaps before settling input, leaving the PoolManager with no physical input token for a hook to `take` in `beforeSwap`. Our compatible [`YieldSwapRouter`](src/uniswap/YieldSwapRouter.sol) syncs and settles exact input in the same unlock **before** calling `swap`. [`YieldMarketHook`](src/uniswap/YieldMarketHook.sol) then takes the physical token, settles output, returns deltas that zero the normal pool swap, and updates its own reserves. The Foundry test uses the real v4 `PoolManager` and covers buy, sell, yield attribution, maturity and LP withdrawal.

It would help developers if the custom-accounting guide included an end-to-end example of hook-owned inventory with a compatible router and explained which common router action orders can fund a `beforeSwap` `take`. Explicit guidance on yield-bearing tokens held by PoolManager versus a hook would also prevent incorrect LP yield claims.

This file is repository feedback for a future developer-feedback submission. No form submission or Sepolia trade is claimed.
