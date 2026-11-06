# RiskFi V2 testnet deployment

The active application uses V2 contracts. Addresses and transaction hashes are in [v2-testnets.json](deployments/v2-testnets.json). Ethereum Sepolia hosts the report, vault, REP, YT, Uniswap v4 market, and CCIP receiver. Arbitrum Sepolia hosts the CCIP sender. The already registered six-decimal DemoUSD token and BurnMintTokenPool exist on both testnets.

## Funding

Fund the **signing wallet** (the address derived from `DEPLOYER_PRIVATE_KEY`) with test ETH on **both** testnets. The Arbitrum Sepolia wallet pays the source gas and native ETH CCIP fee; the Ethereum Sepolia wallet pays deployments and market transactions. Fund or mint Arbitrum Sepolia DemoUSD to the source wallet before a vote. Do not send fee ETH directly to the CCIP router or sender: `CCIPStakeSenderV2.stakeRemote` forwards the attached native fee to the router. The live 5 dUSD test quoted 744250004505817 wei; each send must quote again because fees vary.

The current signer is `0xd561d3e95a02fDD8DbC94d15BFBF1b1634234b3a`. Use `cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY"` locally to confirm it matches your `.env` before signing. `.env` is ignored by Git; never commit the key.

## V2 deployment sequence

The following scripts were run on testnets. They use the `.env` fields in [`.env.example`](.env.example). Source code verification uses `--verify --etherscan-api-key "$ETHERSCAN_API_KEY"` for deployment scripts; generated contracts such as REP, YT, and the hook may need a separate `forge verify-contract` after Etherscan indexes their creation transaction.

1. On Ethereum Sepolia, `DeployV2Sepolia` creates a fresh `ReportRegistry`, `RiskFiStakeVaultV2` (which creates REP), and `CCIPStakeReceiverV2`.
2. On Arbitrum Sepolia, `DeployV2Source` creates `CCIPStakeSenderV2`. On Ethereum Sepolia, `ConfigureV2Lane` allowlists that sender in the receiver.
3. On Ethereum Sepolia, `PublishV2Report` publishes a reviewer-signed report and initializes its YT series. On Arbitrum Sepolia, `ConfigureV2SourceCutoff` sets the same report's source cutoff.
4. On Ethereum Sepolia, `DeployV2Factory` and `DeployV2Hook` mine the hook permission bits, initialize the actual v4 PoolManager pool, and deploy the compatible swap and atomic routers.
5. On Ethereum Sepolia, `SeedV2Pool` stakes 100 dUSD Yes and supplies 50 dUSD plus 100 YT as initial LP inventory. `TradeV2Market` buys and sells YT and atomically stakes 10 dUSD No while selling its new YT.
6. On Arbitrum Sepolia, `SendV2CCIP` sent a 5 dUSD No stake with a V2 token-plus-data message. The first destination attempt [failed](https://sepolia.etherscan.io/tx/0x9e16a3dccbb9215668b02b55ab7391b4d775bda8bf9ac582a0cf66d199401ea0) with `ReceiverError(bytes)` and empty inner data. A retry with a 1,500,000 receiver callback gas override and a 5,000,000 outer transaction gas limit [succeeded](https://sepolia.etherscan.io/tx/0x9402e5d2292c1e0f3862678fc8e86eec1d479013a5d0dd0c08a25ccc6f38b9b1). The [CCIP message](https://ccip.chain.link/#/side-drawer/msg/0xaed819aad1fde53644aa058481a0f606f0ae2e9f78a9bbf2a3264e8c4db1456d) is `SUCCESS`; `delivered(messageId) = true`, the wallet's No position is 15 dUSD, and its YT balance after delivery was 5.000232 YT. Future sends now default to a 1,500,000 receiver gas limit; set `V2_CCIP_NONCE=2` for the next send from this wallet. For another retry, fetch the public `execution-inputs` JSON and use [`RetryV2CCIP.s.sol`](script/RetryV2CCIP.s.sol); set a sufficiently high **outer** transaction gas limit as well as the callback override.
7. On Ethereum Sepolia, `ExerciseV2Yield` injected 10 dUSD simulated yield and claimed 9.999977 dUSD for the LP and 0.000021 dUSD for directly held YT. After CCIP delivery, a second 10 dUSD injection paid 9.565196 dUSD to the LP and [0.434802 dUSD to the cross-chain YT holder](https://sepolia.etherscan.io/tx/0x2ec3844e8ddfe4627488fadad6a3ab57dd8543125b936168ee96ec550d64039d). Run it again only if another demo yield period is intended.

The V2 report has `lockTime = 1794210240`, `crossChainCutoff = 1794123840`, and `maturity = 1796802240` (Unix seconds). V2 settlement can only happen after maturity; the local [end-to-end test](V2_E2E.md) advances time to exercise challenge, adjudication, payout, and sweep. A deployed-state fork can test those future phases before the real clock reaches maturity.

## Checks and limitations

Run `forge test --match-path 'test/*V2.t.sol' --summary` for the 25 V2-only local tests and `forge test --summary` with both RPC URLs for all 29 tests, including the PoolManager and deployed-state forks. The test token is not Circle USDC and `injectYield` is a simulated demo action. A failed swap transaction on Sepolia used an insufficient gas limit before the successful live buy/sell run; use an adequate gas-estimate multiplier for this custom-accounting hook.
