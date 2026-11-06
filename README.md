# SmartContracts

Foundry implementation of the [Mumbai build plan](RiskFi_Mumbai_Final_Build_Plan1.md). The repository records contract work in separate dated Git commits. For the two-chain demo, the collateral is **DemoUSD (`dUSD`)**, a six-decimal test token—not Circle USDC or a dollar-backed asset. The vault yield is simulated. The deployed and verified testnet contracts are recorded in [deployments/testnets.json](deployments/testnets.json); no report, YT series, or Uniswap hook pool has been deployed yet.

## Build and test

Install Foundry, then from this directory:

```sh
forge install smartcontractkit/chainlink-ccip --no-git --shallow
forge install smartcontractkit/chainlink-evm --no-git --shallow
forge install OpenZeppelin/openzeppelin-contracts@v4.9.6 --no-git --shallow
forge install Uniswap/v4-core --no-git --shallow
forge build
forge test
forge fmt --check
```

The dependencies live under ignored `lib/`. The source imports the official [Chainlink CCIP contracts](https://github.com/smartcontractkit/chainlink-ccip), Chainlink's [BurnMintERC20](https://github.com/smartcontractkit/chainlink-evm), and [Uniswap v4 core](https://github.com/Uniswap/v4-core). The current local build uses Solidity 0.8.26. Pin dependency revisions before a production release.

See [DEPLOYMENT.md](DEPLOYMENT.md) for the Ethereum Sepolia and Arbitrum Sepolia sequence, `.env` fields, CCIP pool registration, and explorer verification.

## Uniswap v4 integration for judges

The [developer feedback file](FEEDBACK.md) describes the implementation challenge and documentation requests. The [Uniswap Developer Feedback Form](https://developers.uniswap.org/hackathon-feedback) still needs a team submission containing the public URL of that file.

| What to inspect | Exact implementation | Test |
|---|---|---|
| V2 time-aware rate curve and matching quotes | [`quoteBuy`](src/v2/YieldCurveHookV2.sol#L124), [`quoteSell`](src/v2/YieldCurveHookV2.sol#L139) | [Quote/swap parity and rate changes](test/YieldCurveV2.t.sol#L60) |
| Actual v4 custom-accounting swap | [`beforeSwap`](src/v2/YieldCurveHookV2.sol#L270), [input-first `YieldSwapRouter`](src/uniswap/YieldSwapRouter.sol#L47) | [Local V2 swap test](test/YieldCurveV2.t.sol#L60) |
| Permission-bit hook creation and pool initialization | [`deployAndInitialize`](src/v2/YieldCurveFactoryV2.sol#L22) | [Mined hook test](test/YieldCurveV2.t.sol#L124) |
| LP-owned liquidity and YT yield accounting | [`addLiquidity`](src/v2/YieldCurveHookV2.sol#L188), [`claimLPYield`](src/v2/YieldCurveHookV2.sol#L238) | [Eight-voter workflow](test/EightVoterWorkflowV2.t.sol#L160) |
| Stake and sell newly minted YT atomically | [`stakeAndSellYield`](src/v2/StakeAndSellRouterV2.sol#L48) | [Atomic execution and rollback](test/StakeAndSellV2.t.sol#L85) |

All 25 V2-only local tests pass. The separate Sepolia PoolManager fork test is currently blocked by a public RPC error. The V2 hook, router, and pool are **not deployed**; no live V2 swap or feedback-form submission is claimed.

The active demo flow is V2: REP deposit, staker-owned YT, time-aware Uniswap market, and Chainlink CCIP funded vote. It is implemented under [`src/v2`](src/v2) and summarized in [V2_REVIEW.md](V2_REVIEW.md). Run the [V2-only end-to-end test](V2_E2E.md) with `forge test --match-path 'test/*V2.t.sol' --summary`. V2 is local-only pending review; the deployed V1 contracts have not been replaced.

The active end-to-end local regressions are [`EightVoterWorkflowV2.t.sol`](test/EightVoterWorkflowV2.t.sol) (eight voters including a mock CCIP-funded V2 stake, REP, tradable YT, yield, and verdict), [`CCIPV2.t.sol`](test/CCIPV2.t.sol) (V2 funded message and deferred REP cases), and [`RepReceiptV2.t.sol`](test/RepReceiptV2.t.sol) (REP backing and withdrawal).

## Legacy V1 contract map (not used in the V2 demo)

| Area | Contracts | What the tests establish |
|---|---|---|
| Publication | [`ReportRegistry`](src/ReportRegistry.sol) | Only publisher submits; reviewer signature binds both hashes, report settings, nonce, expiry, chain and registry. |
| Funded votes | [`VoteMarket`](src/VoteMarket.sol), [`VotingPositionToken`](src/VotingPositionToken.sol), [`Settlement`](src/Settlement.sol) | Measured USDC deposits mint VPT; Yes/No payouts, 20% fee on losing pool, Void, repeat claim and 90-day claim window. |
| Chainlink CCIP | [`DemoUSD`](src/DemoUSD.sol), [`CCIPStakeSender`](src/ccip/CCIPStakeSender.sol), [`CCIPStakeReceiver`](src/ccip/CCIPStakeReceiver.sol), [`StakeIntent`](src/ccip/StakeIntent.sol) | Official BurnMintERC20, BurnMintTokenPool, `Client`, `IRouterClient`, and `CCIPReceiver` types; a mock router delivers funds and data to credit a VPT, while late delivery is recoverable. |
| Principal and yield | [`YieldVaultAdapter`](src/yield/YieldVaultAdapter.sol), [`YieldSplitter`](src/yield/YieldSplitter.sol), [`PrincipalToken`](src/yield/PrincipalToken.sol), [`YieldToken`](src/yield/YieldToken.sol) | One report locks at the precommitted time; PT is escrowed; ERC-20 YT checkpoints holder accrual; simulated loss scales principal payouts pro rata. |
| Uniswap v4 | [`YieldMarketHook`](src/uniswap/YieldMarketHook.sol), [`YieldLPShare`](src/uniswap/YieldLPShare.sol), [`YieldSwapRouter`](src/uniswap/YieldSwapRouter.sol), [`Treasury`](src/Treasury.sol) | Official `PoolManager` executes buy/sell through a compatible prepay router; hook owns swap inventory and attributes YT income to LP shares; LP withdrawal works after maturity. |
| Human reputation | [`Reputation`](src/Reputation.sol) | Backend-signed, report-scoped nullifier can mint one non-transferable badge to an eligible winning wallet; cash redemption has no IDKit gate. |

The specific sponsor proofs are in [`test/DemoUSD.t.sol`](test/DemoUSD.t.sol), [`test/CCIP.t.sol`](test/CCIP.t.sol), [`test/UniswapHook.t.sol`](test/UniswapHook.t.sol), and [`test/Voting.t.sol`](test/Voting.t.sol). The Uniswap test deploys the actual v4 `PoolManager`, etches the hook at the required permission bits, initializes its pool, and buys and sells through `YieldSwapRouter`. The two-period test distributes 25 simulated six-decimal dollar units of yield across traders and LPs, allowing only rounding dust.

## Contract economics

- Deposit cutoff is `lockTime`; the 30-day observation and yield period starts then. Source CCIP entry closes earlier. A deposit delivered after `lockTime` is held for recovery.
- Winner nominal payout is `stake + floor(stake × (losingPool − floor(losingPool / 5)) / winningPool)`. The treasury fee is `floor(losingPool / 5)`. Losers get zero. Void refunds accepted principal without a fee.
- If the simulated vault has lost principal when settlement prepares, every nominal payout and fee is multiplied by `availablePrincipal / originalPrincipal`; settlement sweeps final rounding dust after claims expire. Previously distributed yield cannot be clawed back by a later vault loss.
- PT is non-transferable and belongs to Settlement escrow. YT belongs to the Treasury at issue and earns recognized collateral-token yield while held. Selling YT transfers future yield rights, while earlier earned amounts remain with the previous holder.
- Only one report can enter the initial splitter/YT series. Publish additional reports only with a separate configured market and splitter.

## Deployment gates

The token pools, Sepolia core contracts, and Arbitrum sender are deployed and verified. A live funded CCIP vote and Uniswap swap are still outstanding. Before judges can be shown those integrations:

1. The official [Chainlink directory](https://docs.chain.link/ccip/directory/testnet/chain/ethereum-testnet-sepolia-arbitrum-1) lists Arbitrum Sepolia → Ethereum Sepolia as a CCIP 2.0 lane. The DemoUSD pools are registered on both chains, and `PreflightSource` returned a live **token + data** `getFee` quote. Publish a reviewed report, configure `CCIPStakeSender`'s per-report cutoff, then demonstrate a funded delivery and destination VPT credit.
2. Deploy the v4 hook to a mined address with exactly its declared permission flags. Configure the exact PoolKey, then run a buy, sell, LP yield claim and post-maturity withdrawal against Sepolia's deployed PoolManager using the compatible `YieldSwapRouter`. The standard swap-first router path does not prepay input for this hook.
3. Replace the explicitly simulated vault only after validating a real Sepolia yield market for the exact accepted token, withdrawal behavior and principal loss cases. The mock's injected yield is not lending income; DemoUSD has no independent dollar value or Aave market.
4. Integrate Agent Pass server verification and World IDKit Proof of Human verification. The contracts validate signed authorizations but cannot themselves prove that a backend checked the World result. Keep backend signing keys off the frontend.
5. Run live receipt and swap smoke tests, export the transaction links, and submit the Uniswap feedback form. The deployed contracts are recorded, but no feedback form submission is claimed here.

The source's `extraArgs` remain caller-supplied because CCIP lane execution settings vary. The receiver uses an authorized recovery operator for malformed messages without a decodable recipient; this is a custodial recovery authority that needs an operational policy before funds are accepted.
