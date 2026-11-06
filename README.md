# RiskFi V2 smart contracts

RiskFi V2 is a Foundry demo of funded Yes/No reports, a 1:1 collateral receipt (REP), staker-owned yield tokens (YT), a Uniswap v4 YT/dUSD market, and an Arbitrum Sepolia → Ethereum Sepolia Chainlink CCIP funded vote. The active application uses **V2 only**. Earlier V1 application contracts, scripts, and tests were removed from this branch; their Git history remains. The six-decimal `DemoUSD` token and its registered Chainlink BurnMintTokenPools are shared testnet infrastructure, not Circle USDC or a dollar-backed asset. Yield is simulated, not lending income.

## Judge links

| What to verify | Contract entry point | Test or onchain evidence |
|---|---|---|
| Reviewer-approved report | [`ReportRegistry.publish`](src/ReportRegistry.sol#L28) | [V2 report transaction](https://sepolia.etherscan.io/tx/0x4ca1797532d3836d0942be6ac20d87052c6fe873d245009c7bb006671a3df1cd) |
| Deposit → REP → verdict position + YT | [`RiskFiStakeVaultV2.deposit`](src/v2/RiskFiStakeVaultV2.sol#L76), [`stakeFromREP`](src/v2/RiskFiStakeVaultV2.sol#L90), [`stake`](src/v2/RiskFiStakeVaultV2.sol#L100) | [Eight-voter end-to-end test](test/EightVoterWorkflowV2.t.sol#L160) |
| CCIP token-plus-data source | [`CCIPStakeSenderV2.stakeRemote`](src/v2/CCIPStakeSenderV2.sol#L70), [`StakeIntentV2`](src/v2/StakeIntentV2.sol) | [Arbitrum Sepolia source transaction](https://sepolia.arbiscan.io/tx/0x4f4e9a9f44ce28fb65ca80c5ba19a6ccda56223156e6e90d33884ffc18a99de2) |
| CCIP destination credit and REP fallback | [`CCIPStakeReceiverV2._ccipReceive`](src/v2/CCIPStakeReceiverV2.sol#L50) | [V2 CCIP tests](test/CCIPV2.t.sol) and [message tracker](https://ccip.chain.link/#/side-drawer/msg/0xaed819aad1fde53644aa058481a0f606f0ae2e9f78a9bbf2a3264e8c4db1456d) |
| Uniswap v4 rate curve and quotes | [`quoteBuy`](src/v2/YieldCurveHookV2.sol#L124), [`quoteSell`](src/v2/YieldCurveHookV2.sol#L139) | [Quote and swap tests](test/YieldCurveV2.t.sol#L60) |
| v4 custom-accounting swap | [`beforeSwap`](src/v2/YieldCurveHookV2.sol#L270), [`YieldSwapRouter.unlockCallback`](src/uniswap/YieldSwapRouter.sol#L47) | [Live buy](https://sepolia.etherscan.io/tx/0x5e1bf9e88d2cfe91752b076334058670ecdb874909ecd0663aa6678c9b737027), [live sell](https://sepolia.etherscan.io/tx/0xdb2a2da2e3097db60a3a334622ccb72ab9839b52bb284acb0e171a1f8dbbab25) |
| Hook permission bits and pool initialization | [`YieldCurveFactoryV2.deployAndInitialize`](src/v2/YieldCurveFactoryV2.sol#L22) | [Live pool creation](https://sepolia.etherscan.io/tx/0x61b15809af0f0af4af23e099afe327c76fc6c2afdf3b35c8c896798fa7808c) |
| LP-owned YT inventory and yield | [`addLiquidity`](src/v2/YieldCurveHookV2.sol#L188), [`claimLPYield`](src/v2/YieldCurveHookV2.sol#L238) | [Live liquidity](https://sepolia.etherscan.io/tx/0x076b98e0b8a1aeb43ded81737de69bc09a2ea11830e6ec4466bd3850b82e493f) |
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

The local V2 suite has **25 passing tests**. `test/DemoUSD.t.sol` separately checks the official Chainlink token pool setup. `test/V2LivePoolFork.t.sol` runs against a local fork of Sepolia's deployed PoolManager when `ETH_SEPOLIA_RPC_URL` is set; this test passed with the Tenderly public RPC. The fork sends no transaction to Sepolia.

## Deployment and time limits

The V2 contracts are deployed and verified on Ethereum Sepolia and Arbitrum Sepolia. The current CCIP message was sent from Arbitrum Sepolia; [its status](https://ccip.chain.link/#/side-drawer/msg/0xaed819aad1fde53644aa058481a0f606f0ae2e9f78a9bbf2a3264e8c4db1456d) must be checked before claiming destination credit. V2 fixes maturity at **30 days after the report lock**. Live verdict finalization and principal redemption cannot happen before then; a local fork can advance time to test those phases against deployed bytecode and state.

The onchain report uses one vault and one YT series. It is a public demo: stakes and sides are visible, REP is a collateral receipt, the verdict position cannot be transferred, and the YT is transferable. Existing V1 contracts remain onchain but are not part of the active V2 workflow.
