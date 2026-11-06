# RiskFi V2 smart contracts

RiskFi V2 is a Foundry demo of funded Yes/No reports, a 1:1 collateral receipt (REP), staker-owned yield tokens (YT), a Uniswap v4 YT/dUSD market, and an Arbitrum Sepolia → Ethereum Sepolia Chainlink CCIP funded vote. The active application uses **V2 only**. Earlier V1 application contracts, scripts, and tests were removed from this branch; their Git history remains. The six-decimal `DemoUSD` token and its registered Chainlink BurnMintTokenPools are shared testnet infrastructure, not Circle USDC or a dollar-backed asset. Yield is simulated, not lending income.

Review the live demo step by step in [V2_TRANSACTION_WALKTHROUGH.md](V2_TRANSACTION_WALKTHROUGH.md); every onchain step links to its transaction.

## Judge links

| What to verify | Contract entry point | Test or onchain evidence |
|---|---|---|
| Reviewer-approved report | [`ReportRegistry.publish`](src/ReportRegistry.sol#L28) | [V2 report transaction](https://sepolia.etherscan.io/tx/0x4ca1797532d3836d0942be6ac20d87052c6fe873d245009c7bb006671a3df1cd) |
| Configurable demo clock (new deployments) | [`FlexibleReportRegistry.publish`](src/v2/FlexibleReportRegistry.sol), [`RiskFiStakeVaultV2.initializeSeries`](src/v2/RiskFiStakeVaultV2.sol) | [10-minute vote, post-lock trade, and one-hour settlement tests](test/FlexibleReportV2.t.sol) |
| Public test dUSD mint | [`PublicDemoUSDFaucet.claim`](src/v2/PublicDemoUSDFaucet.sol) | [Sepolia claim](https://sepolia.etherscan.io/tx/0xde57b6ab8c29d5b7a6e3ba1979707261cff78e1f55ebc6a5f2510e855369e70d), [Arbitrum Sepolia claim](https://sepolia.arbiscan.io/tx/0x0a3754a62343b0bb12689848769b53f0517bfdb83c6a66c9c969a5e561ca34fd) |
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

The local V2 suite has **30 passing tests**, including two public faucet tests. `test/DemoUSD.t.sol` separately checks the official Chainlink token pool setup. `test/V2LivePoolFork.t.sol` runs against a local fork of Sepolia's deployed PoolManager. `test/V2DeployedFork.t.sol` checks the live V2 source and destination wiring, then advances a local Sepolia fork to the report's maturity for dispute, payout, and LP exit. With RPC URLs set, the complete suite has **34 passing tests**. Fork tests send no transaction to either testnet.

## Deployment and time limits

The original V2 contracts are deployed and verified on Ethereum Sepolia and Arbitrum Sepolia. The 5 dUSD No vote sent from Arbitrum Sepolia reached [CCIP SUCCESS](https://ccip.chain.link/#/side-drawer/msg/0xaed819aad1fde53644aa058481a0f606f0ae2e9f78a9bbf2a3264e8c4db1456d) after a higher-gas manual retry. The original registry and vault fix maturity at **30 days after the report lock**; they cannot settle sooner. A local fork advances time to test those phases against deployed bytecode and state.

For a fresh accelerated report, `FlexibleReportRegistry` records a reviewer-signed maturity timestamp per report. A newly deployed `RiskFiStakeVaultV2` reads that timestamp on initialization; the original deployed vault is unchanged. `demo/accelerated-report.json` is synthetic data, not a research assessment. The scripts `DeployFlexibleV2Sepolia.s.sol` and `PublishFlexibleV2Report.s.sol` prepare a new registry/vault/CCIP receiver and publish a report with `V2_REMOTE_CUTOFF_SECONDS`, `V2_VOTE_SECONDS`, `V2_TRADE_SECONDS`, `V2_CHALLENGE_SECONDS`, and `V2_RESULT_SECONDS`. For a one-hour test, use 300, 600, 3000, 300, and 3600 seconds respectively. Prepare the frontend and deployment automation before starting the short clock; the new YT market can only be deployed after publication initializes the YT token. A CCIP transfer may arrive after a 10-minute vote lock and then become withdrawable REP instead of a counted vote.

The registry, vault, REP and CCIP adapters for the accelerated demo are already deployed and wired; [prepared addresses and transactions](deployments/v2-flexible-prepared.json) record them. The registry still has no report. After publishing and deploying the new YT hook, run `python3 script/build_flexible_handoff.py --hook-log /path/to/hook-deployment.log` to generate the address/ABI bundle for the frontend. It checks the onchain report hash against the synthetic JSON, the Arbitrum cutoff, vault series, and hook LP share before writing the bundle.

## Public dUSD test faucets

The existing dUSD token on each testnet has granted `MINTER_ROLE` to a separate [public faucet](deployments/public-dusd-faucets.json). Anyone with gas on that chain can connect a wallet to the verified faucet contract and call `claim()` to mint **100 dUSD to themselves**; they can repeat after 60 seconds. The faucet has no function to mint to another address. Both networks' deployer test claims succeeded, and a read-only call from an unrelated address succeeded on each chain. The token and CCIP BurnMint pools were not redeployed. dUSD is a test token with no dollar backing.

The onchain report uses one vault and one YT series. It is a public demo: stakes and sides are visible, REP is a collateral receipt, the verdict position cannot be transferred, and the YT is transferable. Existing V1 contracts remain onchain but are not part of the active V2 workflow.

## Per-report V2 market infrastructure (November 2026)

Fresh reports from either registry can now get their own vault, YT, Uniswap v4 market, and Chainlink CCIP path without redeploying the registries or changing the existing report #1 deployments. The publisher follows these onchain steps before the relevant clocks close:

1. [`V2SeriesFactory.prepare`](src/v2/V2SeriesFactory.sol) deploys the report's vault, REP, and YT. Sepolia factory: [`0xc5895A4C15E1e9e3e7fdAa56e8cDC60c8465C61a`](https://sepolia.etherscan.io/address/0xc5895A4C15E1e9e3e7fdAa56e8cDC60c8465C61a).
2. [`V2HookSaltFinder.find`](src/v2/V2HookSaltFinder.sol) searches a CREATE2 salt with the required v4 hook permission bits. [`YieldCurveFactoryV2.deployAndInitialize`](src/v2/YieldCurveFactoryV2.sol) deploys and initializes the YT/dUSD pool. Sepolia finder: [`0x8Ae0e98B661f89A06BCE49C4155E3b272D63d7bf`](https://sepolia.etherscan.io/address/0x8Ae0e98B661f89A06BCE49C4155E3b272D63d7bf).
3. [`V2PoolCatalog.activate`](src/v2/V2PoolCatalog.sol) verifies the pool, creates the atomic stake and sell router plus the CCIP receiver, and stores the report's market addresses. Sepolia catalog: [`0xf1e4F220F7b537e9270D52eb32db6105271F11B9`](https://sepolia.etherscan.io/address/0xf1e4F220F7b537e9270D52eb32db6105271F11B9).
4. [`V2CCIPSenderFactory.deploy`](src/v2/V2CCIPSenderFactory.sol) creates the Arbitrum Sepolia sender with the report's remote cutoff. Arbitrum factory: [`0x116d26F06bC7455C63A45D832586ea8F9Ac29B41`](https://sepolia.arbiscan.io/address/0x116d26F06bC7455C63A45D832586ea8F9Ac29B41). The publisher calls [`configureSourceSender`](src/v2/CCIPStakeReceiverV2.sol) on the corresponding Sepolia receiver to complete the trust link.

`test/V2MarketSetup.t.sol` exercises flexible and original registry publication through market preparation; the flexible path also covers v4 hook deployment, activation, stake, liquidity, and swap. `test/V2CCIPSenderFactory.t.sol` covers the per-report source sender and cutoff. Run `forge test` for the complete suite. The frontend discovers reports and these catalog addresses automatically. A new market needs YT and dUSD liquidity before swaps; CCIP must be configured before the report's cutoff. No new user report has been published through this flow yet.
