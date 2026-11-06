# RiskFi smart contracts

Foundry implementation of the [Mumbai build plan](RiskFi_Mumbai_Final_Build_Plan1.md). The repository records contract work in separate dated Git commits. For the two-chain demo, the collateral is **DemoUSD (`dUSD`)**, a six-decimal test token—not Circle USDC or a dollar-backed asset. The vault yield is simulated. No application contract address in this repository is presented as a live deployment.

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

## Contract map

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

The repository has **local proof**, not completed sponsor deployment proof. Before judges can be shown a live integration:

1. The official [Chainlink directory](https://docs.chain.link/ccip/directory/testnet/chain/ethereum-testnet-sepolia-arbitrum-1) lists Arbitrum Sepolia → Ethereum Sepolia as a CCIP 2.0 lane, and `PreflightLane` confirmed `isChainSupported` on the live router. Deploy/register DemoUSD BurnMintTokenPool on both chains, configure each remote token/pool, then run `PreflightSource` to prove a **token + data** `getFee` quote. Configure `CCIPStakeSender`'s per-report cutoff before remote entry.
2. Deploy the v4 hook to a mined address with exactly its declared permission flags. Configure the exact PoolKey, then run a buy, sell, LP yield claim and post-maturity withdrawal against Sepolia's deployed PoolManager using the compatible `YieldSwapRouter`. The standard swap-first router path does not prepay input for this hook.
3. Replace the explicitly simulated vault only after validating a real Sepolia yield market for the exact accepted token, withdrawal behavior and principal loss cases. The mock's injected yield is not lending income; DemoUSD has no independent dollar value or Aave market.
4. Integrate Agent Pass server verification and World IDKit Proof of Human verification. The contracts validate signed authorizations but cannot themselves prove that a backend checked the World result. Keep backend signing keys off the frontend.
5. Deploy with user-controlled keys, verify contracts on explorers, run live receipt and swap smoke tests, export addresses/transactions, and submit the Uniswap feedback form. No deployment or feedback submission is claimed here.

The source's `extraArgs` remain caller-supplied because CCIP lane execution settings vary. The receiver uses an authorized recovery operator for malformed messages without a decodable recipient; this is a custodial recovery authority that needs an operational policy before funds are accepted.
