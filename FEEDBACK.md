# Uniswap v4 developer feedback — RiskFi

## What we built

RiskFi lets a voter stake six-decimal demo collateral (dUSD) on a report, retain a non-transferable Yes/No verdict position, and receive a transferable yield token (YT). We built a Uniswap v4 YT/dUSD market so the voter can sell future yield while retaining the verdict position. The V2 hook uses a time-aware implied-rate curve, quote functions, hook-owned reserves, and LP shares that receive yield earned by YT in market inventory. A separate atomic router stakes and sells the newly minted YT in one transaction. These are demo contracts: dUSD is not Circle USDC, yield is simulated, and V2 has not been deployed.

## Code and evidence

| Integration | Implementation | Evidence |
|---|---|---|
| v4 hook, quotes, rate curve, custom-accounting swaps | [YieldCurveHookV2 `quoteBuy`](src/v2/YieldCurveHookV2.sol#L123), [`quoteSell`](src/v2/YieldCurveHookV2.sol#L138), [`beforeSwap`](src/v2/YieldCurveHookV2.sol#L254) | [Quote/swap parity and rate movement](test/YieldCurveV2.t.sol#L60), [256-run fuzz test](test/YieldCurveV2.t.sol#L106) |
| Hook deployment and pool initialization with v4 permission bits | [YieldCurveFactoryV2](src/v2/YieldCurveFactoryV2.sol#L22) | [Mined hook and pool test](test/YieldCurveV2.t.sol#L124) |
| LP-owned YT inventory and yield attribution | [Liquidity and LP yield methods](src/v2/YieldCurveHookV2.sol#L149) | [Eight-voter workflow with LP yield](test/EightVoterWorkflowV2.t.sol#L147) |
| Exact-input router that settles input before the hook swap | [YieldSwapRouter](src/uniswap/YieldSwapRouter.sol#L47) | [v4 PoolManager buy/sell test](test/UniswapHook.t.sol#L72) |
| Atomic stake and YT sale | [StakeAndSellRouterV2](src/v2/StakeAndSellRouterV2.sol#L48) | [Stake/sell and slippage rollback](test/StakeAndSellV2.t.sol#L85) |
| Test against Ethereum Sepolia's deployed PoolManager | [Local-fork test](test/V2LivePoolFork.t.sol#L52) | Runs in a local EVM fork; no Sepolia swap transaction is claimed. |
| Cross-chain-funded YT sold through v4 | [CCIP-funded voter integration test](test/EightVoterWorkflowV2.t.sol#L267) | Uses a mock CCIP router and local v4 PoolManager. |

## Blocker and request for developer documentation

The `PoolSwapTest` action sequence we initially used invoked `swap` before physically settling the input token. A hook that owns its reserves and calls `manager.take` during `beforeSwap` needs an action sequence that makes the input available in the same unlock. We built a compatible [exact-input router](src/uniswap/YieldSwapRouter.sol#L47) that syncs and settles input before the swap. An end-to-end custom-accounting example showing the router action order, hook deltas, and token settlement would make this pattern easier to implement and debug.

The second challenge was accounting for yield on YT held by the market. We hold inventory in the hook and attribute its accrued YT yield to explicit LP shares. Documentation comparing yield-bearing tokens held in PoolManager with hook-owned inventory, including who can claim the accrued yield, would help teams avoid incorrect LP accounting.

For a time-aware market, examples showing how to expose quotes that match hook execution, handle rounding and maturity, and test a mined permission-bit hook against a deployed PoolManager would also be useful.

## Feedback form submission

This file provides the technical detail for the [Uniswap Developer Feedback Form](https://developers.uniswap.org/hackathon-feedback). Include this public GitHub file URL in the form's **Any additional feedback** field. Form answers about participant identity, time spent, ratings, and support used should come from the team. **The form has not been submitted.**
