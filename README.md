# RiskFi V2 smart contracts

RiskFi V2 is a Foundry demo of funded Yes/No reports, a 1:1 collateral receipt (REP), staker-owned yield tokens (YT), a Uniswap v4 YT/dUSD market, and an Arbitrum Sepolia → Ethereum Sepolia Chainlink CCIP funded vote. The active application uses **V2 only**. Earlier V1 application contracts, scripts, and tests were removed from this branch; their Git history remains. The six-decimal `DemoUSD` token and its registered Chainlink BurnMintTokenPools are shared testnet infrastructure, not Circle USDC or a dollar-backed asset. Yield is simulated, not lending income.

Review the live demo step by step in [V2_TRANSACTION_WALKTHROUGH.md](V2_TRANSACTION_WALKTHROUGH.md); every onchain step links to its transaction.

## Judge links

| What to verify | Contract entry point | Test or onchain evidence |
|---|---|---|
| Reviewer-approved report | [`ReportRegistry.publish`](src/ReportRegistry.sol#L28) | [V2 report transaction](https://sepolia.etherscan.io/tx/0x4ca1797532d3836d0942be6ac20d87052c6fe873d245009c7bb006671a3df1cd) |
| Configurable demo clock (new deployments) | [`FlexibleReportRegistry.publish`](src/v2/FlexibleReportRegistry.sol), [`RiskFiStakeVaultV2.initializeSeries`](src/v2/RiskFiStakeVaultV2.sol) | [10-minute vote, post-lock trade, and one-hour settlement tests](test/FlexibleReportV2.t.sol) |
| Deposit → REP → verdict position + YT | [`RiskFiStakeVaultV2.deposit`](src/v2/RiskFiStakeVaultV2.sol#L76), [`stakeFromREP`](src/v2/RiskFiStakeVaultV2.sol#L90), [`stake`](src/v2/RiskFiStakeVaultV2.sol#L100) | [Eight-voter end-to-end test](test/EightVoterWorkflowV2.t.sol#L160) |
| CCIP token-plus-data source | [`CCIPStakeSenderV2.stakeRemote`](src/v2/CCIPStakeSenderV2.sol#L70), [`StakeIntentV2`](src/v2/StakeIntentV2.sol) | [Arbitrum Sepolia source transaction](https://sepolia.arbiscan.io/tx/0x4f4e9a9f44ce28fb65ca80c5ba19a6ccda56223156e6e90d33884ffc18a99de2) |
| CCIP destination credit and REP fallback | [`CCIPStakeReceiverV2._ccipReceive`](src/v2/CCIPStakeReceiverV2.sol#L50) | [Successful destination execution](https://sepolia.etherscan.io/tx/0x9402e5d2292c1e0f3862678fc8e86eec1d479013a5d0dd0c08a25ccc6f38b9b1), [V2 CCIP tests](test/CCIPV2.t.sol), [message tracker](https://ccip.chain.link/#/side-drawer/msg/0xaed819aad1fde53644aa058481a0f606f0ae2e9f78a9bbf2a3264e8c4db1456d) |
| Uniswap v4 rate curve and quotes | [`quoteBuy`](src/v2/YieldCurveHookV2.sol#L124), [`quoteSell`](src/v2/YieldCurveHookV2.sol#L139) | [Quote and swap tests](test/YieldCurveV2.t.sol#L60) |
| v4 custom-accounting swap | [`beforeSwap`](src/v2/YieldCurveHookV2.sol#L270), [`YieldSwapRouter.unlockCallback`](src/uniswap/YieldSwapRouter.sol#L47) | [Live buy](https://sepolia.etherscan.io/tx/0x5e1bf9e88d2cfe91752b076334058670ecdb874909ecd0663aa6678c9b737027), [live sell](https://sepolia.etherscan.io/tx/0xdb2a2da2e3097db60a3a334622ccb72ab9839b52bb284acb0e171a1f8dbbab25) |
| Hook permission bits and pool initialization | [`YieldCurveFactoryV2.deployAndInitialize`](src/v2/YieldCurveFactoryV2.sol#L22) | [Live pool creation](https://sepolia.etherscan.io/tx/0x61b15809af0f0af4af23e099afe327c76fc6c6c2afdf3b35c8c896798fa7808c) |
| LP-owned YT inventory and yield | [`addLiquidity`](src/v2/YieldCurveHookV2.sol#L188), [`claimLPYield`](src/v2/YieldCurveHookV2.sol#L238) | [Live liquidity](https://sepolia.etherscan.io/tx/0x076b98e0b8a1aeb43ded81737de69bc09a2ea11830e6ec4466bd3850b82e493f), [live yield injection](https://sepolia.etherscan.io/tx/0xe837d7ff95efc98d4921a7c3bdd2ad50d12b29c57bd862e21c8f4cef2176c9ec), [LP yield claim](https://sepolia.etherscan.io/tx/0x7fc2d0effd7f918e72022f1f1f5bc485da7f5d7ca82802836751aead261e4568) |
| Atomic stake and YT sale | [`StakeAndSellRouterV2.stakeAndSellYield`](src/v2/StakeAndSellRouterV2.sol#L48) | [Live atomic transaction](https://sepolia.etherscan.io/tx/0x8f5e454b971a1b3a19a684b1ca47bcd1916250b706148329456292e8e7a0a63a) |
| Final verdict and payout | [`propose`](src/v2/RiskFiStakeVaultV2.sol#L151), [`adjudicate`](src/v2/RiskFiStakeVaultV2.sol#L172), [`claimPrincipal`](src/v2/RiskFiStakeVaultV2.sol#L216) | [Local eight-voter end-to-end test](test/EightVoterWorkflowV2.t.sol#L160) |

See [V2 testnet deployment addresses](deployments/v2-testnets.json), [deployment instructions](DEPLOYMENT.md), [end-to-end test record](V2_E2E.md), and [Uniswap feedback](FEEDBACK.md). The feedback form still needs a team submission with the public `FEEDBACK.md` URL.

## Build and test

Install Foundry and the dependencies in `lib/`, then run:

```sh
forge install smartcontractkit/chainlink-ccip --no-git --shallow
forge install smartcontractkit/chainlink-evm --no-git --shallow
forge install OpenZeppelin/openzeppelin-contracts@v4.9.6 --no-git --shallow
forge install Uniswap/v4-core --no-git --shallow
forge build
forge fmt --check
forge test --match-path 'test/*V2.t.sol' --summary
```

The local V2 suite has **28 passing tests**. `test/DemoUSD.t.sol` separately checks the official Chainlink token pool setup. `test/V2LivePoolFork.t.sol` runs against a local fork of Sepolia's deployed PoolManager. `test/V2DeployedFork.t.sol` checks the live V2 source and destination wiring, then advances a local Sepolia fork to the report's maturity for dispute, payout, and LP exit. With RPC URLs set, the complete suite has **32 passing tests**. Fork tests send no transaction to either testnet.

## Deployment and time limits

The original V2 contracts are deployed and verified on Ethereum Sepolia and Arbitrum Sepolia. The 5 dUSD No vote sent from Arbitrum Sepolia reached [CCIP SUCCESS](https://ccip.chain.link/#/side-drawer/msg/0xaed819aad1fde53644aa058481a0f606f0ae2e9f78a9bbf2a3264e8c4db1456d) after a higher-gas manual retry. The original registry and vault fix maturity at **30 days after the report lock**; they cannot settle sooner. A local fork advances time to test those phases against deployed bytecode and state.

For a fresh accelerated report, `FlexibleReportRegistry` records a reviewer-signed maturity timestamp per report. A newly deployed `RiskFiStakeVaultV2` reads that timestamp on initialization; the original deployed vault is unchanged. `demo/accelerated-report.json` is synthetic data, not a research assessment. The scripts `DeployFlexibleV2Sepolia.s.sol` and `PublishFlexibleV2Report.s.sol` prepare a new registry/vault/CCIP receiver and publish a report with `V2_REMOTE_CUTOFF_SECONDS`, `V2_VOTE_SECONDS`, `V2_TRADE_SECONDS`, `V2_CHALLENGE_SECONDS`, and `V2_RESULT_SECONDS`. For a one-hour test, use 300, 600, 3000, 300, and 3600 seconds respectively. Prepare the frontend and deployment automation before starting the short clock; the new YT market can only be deployed after publication initializes the YT token. A CCIP transfer may arrive after a 10-minute vote lock and then become withdrawable REP instead of a counted vote.

The onchain report uses one vault and one YT series. It is a public demo: stakes and sides are visible, REP is a collateral receipt, the verdict position cannot be transferred, and the YT is transferable. Existing V1 contracts remain onchain but are not part of the active V2 workflow.
