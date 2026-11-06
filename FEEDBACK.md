# Uniswap v4 developer feedback — RiskFi

## What we built

RiskFi V2 lets a voter deposit six-decimal demo collateral (dUSD) and receive a 1:1 REP receipt. Staking burns REP, creates a non-transferable Yes/No verdict position, and mints a transferable yield token (YT) to the staker. We built a Uniswap v4 YT/dUSD market so the voter can sell future yield while retaining the verdict position. The V2 hook uses a time-aware implied-rate curve, quote functions, hook-owned reserves, and LP shares that receive yield earned by YT in market inventory. A separate atomic router stakes and sells the newly minted YT in one transaction. These are demo contracts: dUSD is not Circle USDC and yield is simulated. V2 contracts and the v4 pool are deployed on Ethereum Sepolia.

## Code and evidence

| Integration | Implementation | Evidence |
|---|---|---|
| v4 hook, quotes, rate curve, custom-accounting swaps | [YieldCurveHookV2 `quoteBuy`](src/v2/YieldCurveHookV2.sol#L124), [`quoteSell`](src/v2/YieldCurveHookV2.sol#L139), [`beforeSwap`](src/v2/YieldCurveHookV2.sol#L270) | [Quote/swap parity and rate movement](test/YieldCurveV2.t.sol#L60), [256-run fuzz test](test/YieldCurveV2.t.sol#L106) |
| Hook deployment and pool initialization with v4 permission bits | [YieldCurveFactoryV2](src/v2/YieldCurveFactoryV2.sol#L22) | [Mined hook and pool test](test/YieldCurveV2.t.sol#L124) |
| LP-owned YT inventory and yield attribution | [`addLiquidity`](src/v2/YieldCurveHookV2.sol#L188), [`claimLPYield`](src/v2/YieldCurveHookV2.sol#L238) | [Eight-voter workflow with LP yield](test/EightVoterWorkflowV2.t.sol#L160) |
| Exact-input router that settles input before the hook swap | [YieldSwapRouter](src/uniswap/YieldSwapRouter.sol#L47) | [V2 quote/swap parity test](test/YieldCurveV2.t.sol#L60), [live buy](https://sepolia.etherscan.io/tx/0x5e1bf9e88d2cfe91752b076334058670ecdb874909ecd0663aa6678c9b737027) |
| Atomic stake and YT sale | [StakeAndSellRouterV2](src/v2/StakeAndSellRouterV2.sol#L48) | [Stake/sell and slippage rollback](test/StakeAndSellV2.t.sol#L85) |
| V2 REP deposit, stake, and idle collateral protection | [V2 vault](src/v2/RiskFiStakeVaultV2.sol#L76), [REP receipt](src/v2/StakeReceiptREP.sol) | [Eight-voter workflow](test/EightVoterWorkflowV2.t.sol#L160), [REP collateral test](test/RepReceiptV2.t.sol#L122) |
| Cross-chain-funded YT sold through v4 | [CCIP-funded voter integration test](test/EightVoterWorkflowV2.t.sol#L297) | Uses separate mock source and destination tokens, a local CCIP router, and a local v4 PoolManager. |
| Test against Ethereum Sepolia's deployed PoolManager | [Local-fork test](test/V2LivePoolFork.t.sol#L52) | Passed using the Tenderly public RPC. |

The [V2 end-to-end record](V2_E2E.md) covers report approval, eight funded votes, REP receipt and burn, delayed mock CCIP delivery, YT trades, two yield periods, a challenged verdict, principal payouts, LP exit, and collateral conservation. All **25 V2-only local tests** pass with `forge test --match-path 'test/*V2.t.sol' --summary`. The separate RPC-dependent fork test is not part of that count.

Live Ethereum Sepolia transactions demonstrate [pool creation](https://sepolia.etherscan.io/tx/0x61b15809af0f0af4af23e099afe327c76fc6c6c2afdf3b35c8c896798fa7808c), [YT buy](https://sepolia.etherscan.io/tx/0x5e1bf9e88d2cfe91752b076334058670ecdb874909ecd0663aa6678c9b737027), [YT sell](https://sepolia.etherscan.io/tx/0xdb2a2da2e3097db60a3a334622ccb72ab9839b52bb284acb0e171a1f8dbbab25), [atomic stake and YT sale](https://sepolia.etherscan.io/tx/0x8f5e454b971a1b3a19a684b1ca47bcd1916250b706148329456292e8e7a0a63a), [10 dUSD demo yield injection](https://sepolia.etherscan.io/tx/0xe837d7ff95efc98d4921a7c3bdd2ad50d12b29c57bd862e21c8f4cef2176c9ec), [LP yield claim](https://sepolia.etherscan.io/tx/0x7fc2d0effd7f918e72022f1f1f5bc485da7f5d7ca82802836751aead261e4568), [successful CCIP destination credit](https://sepolia.etherscan.io/tx/0x9402e5d2292c1e0f3862678fc8e86eec1d479013a5d0dd0c08a25ccc6f38b9b1), and [yield claimed on CCIP-minted YT](https://sepolia.etherscan.io/tx/0x2ec3844e8ddfe4627488fadad6a3ab57dd8543125b936168ee96ec550d64039d). The first CCIP destination attempt needed a higher-gas manual retry; both transactions are recorded in [deployment evidence](deployments/v2-testnets.json). The deployed-state fork tests settlement at future maturity; the live report cannot finalize before its 30-day maturity.

## Blocker and request for developer documentation

The `PoolSwapTest` action sequence we initially used invoked `swap` before physically settling the input token. A hook that owns its reserves and calls `manager.take` during `beforeSwap` needs an action sequence that makes the input available in the same unlock. We built a compatible [exact-input router](src/uniswap/YieldSwapRouter.sol#L47) that syncs and settles input before the swap. An end-to-end custom-accounting example showing the router action order, hook deltas, and token settlement would make this pattern easier to implement and debug.

The second challenge was accounting for yield on YT held by the market. We hold inventory in the hook and attribute its accrued YT yield to explicit LP shares. Documentation comparing yield-bearing tokens held in PoolManager with hook-owned inventory, including who can claim the accrued yield, would help teams avoid incorrect LP accounting.

For a time-aware market, examples showing how to expose quotes that match hook execution, handle rounding and maturity, and test a mined permission-bit hook against a deployed PoolManager would also be useful.

## Feedback form submission

This file provides the technical detail for the [Uniswap Developer Feedback Form](https://developers.uniswap.org/hackathon-feedback). Include the [public GitHub URL for this file](https://github.com/EthGlobal-Mumbai-2026-ScoobyDAO/SmartContracts/blob/main/FEEDBACK.md) in the form's **Any additional feedback** field after confirming it opens while signed out. Form answers about participant identity, time spent, ratings, and support used should come from the team. **The form has not been submitted.**
