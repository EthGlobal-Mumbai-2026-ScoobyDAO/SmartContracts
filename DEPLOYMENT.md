# Testnet deployment and verification

This deployment targets **Ethereum Sepolia** for the market, vault, settlement, reputation, and Uniswap v4 hook. **Arbitrum Sepolia** is only the CCIP source. Collateral is the six-decimal `DemoUSD` test token (`dUSD`) on each chain, bridged with Chainlink's official burn/mint token pools. It is not Circle USDC.

## 1. Environment and independent preflight

`.env.example` records the public addresses from the [Chainlink CCIP directory for Ethereum Sepolia](https://docs.chain.link/ccip/directory/testnet/chain/ethereum-testnet-sepolia), the [Arbitrum Sepolia directory](https://docs.chain.link/ccip/directory/testnet/chain/ethereum-testnet-sepolia-arbitrum-1), and [Uniswap's Sepolia deployments](https://developers.uniswap.org/docs/protocols/v4/deployments). Recheck them before broadcast. `.env` is Git-ignored. Put the funded deployer key there; keep it out of chat, logs, frontend code, and Git.

Create one key in the [Etherscan API dashboard](https://etherscan.io/apidashboard) and set `ETHERSCAN_API_KEY` in `.env`. Etherscan API V2 uses that key for both Ethereum Sepolia and Arbitrum Sepolia; a separate Arbiscan key is unnecessary. See [Etherscan's key setup guide](https://docs.etherscan.io/set-up-your-api-key).

```sh
set -a
source .env
set +a
forge build
forge test
forge fmt --check
forge script script/PreflightLane.s.sol:PreflightLane --rpc-url "$ARB_SEPOLIA_RPC_URL" -vv
```

The last command has already succeeded against the live Arbitrum Sepolia router. It proves the lane exists; it does not prove DemoUSD is registered yet.

## 2. Deploy DemoUSD and register token admins

The same script deploys Chainlink's `BurnMintERC20` derivative and `BurnMintTokenPool` on each chain. It grants the pool mint/burn roles, mints test tokens to the deployer, and claims the token-admin role. It deliberately waits to call `setPool` until both remote pool configurations are complete.

```sh
forge script script/DeployDemoUSD.s.sol:DeployDemoUSD --rpc-url "$ETH_SEPOLIA_RPC_URL" --broadcast --verify --etherscan-api-key "$ETHERSCAN_API_KEY" -vv
forge script script/DeployDemoUSD.s.sol:DeployDemoUSD --rpc-url "$ARB_SEPOLIA_RPC_URL" --broadcast --verify --etherscan-api-key "$ETHERSCAN_API_KEY" -vv
```

Record the two `DemoUSD` and `BurnMintTokenPool` addresses as `SEPOLIA_DEMO_USD`, `SEPOLIA_DEMO_POOL`, `ARBITRUM_DEMO_USD`, and `ARBITRUM_DEMO_POOL` in `.env`. Both token contracts are separate deployments linked by CCIP pool configuration.

```sh
set -a; source .env; set +a
forge script script/ConfigureDemoPool.s.sol:ConfigureDemoPool --rpc-url "$ETH_SEPOLIA_RPC_URL" --broadcast -vv
forge script script/ConfigureDemoPool.s.sol:ConfigureDemoPool --rpc-url "$ARB_SEPOLIA_RPC_URL" --broadcast -vv
forge script script/ActivateDemoPool.s.sol:ActivateDemoPool --rpc-url "$ETH_SEPOLIA_RPC_URL" --broadcast -vv
forge script script/ActivateDemoPool.s.sol:ActivateDemoPool --rpc-url "$ARB_SEPOLIA_RPC_URL" --broadcast -vv
forge script script/PreflightSource.s.sol:PreflightSource --rpc-url "$ARB_SEPOLIA_RPC_URL" -vv
```

`PreflightSource` calls Chainlink's live router `getFee` for a 1 dUSD programmable transfer with data using `ExtraArgsV3`. Stop if it reverts; a deployed token on each chain alone is insufficient. Verify registry `getPool(token)`, both remote pool/token settings, and the destination token address before sending funds.

## 3. Deploy the Sepolia protocol and Arbitrum sender

Set `IDENTITY_SIGNER` to the backend signer address. Until an IDKit backend verifies proofs, that signer is a **mock demo authorization**, not a World identity integration.

```sh
forge script script/DeploySepolia.s.sol:DeploySepolia --rpc-url "$ETH_SEPOLIA_RPC_URL" --broadcast --verify --etherscan-api-key "$ETHERSCAN_API_KEY" -vv
```

Record `CCIPReceiver`, `Splitter`, `Treasury`, and the other printed addresses. Put `CCIPReceiver` in `SEPOLIA_CCIP_RECEIVER`, then deploy the Arbitrum-only sender:

```sh
set -a; source .env; set +a
forge script script/DeploySource.s.sol:DeploySource --rpc-url "$ARB_SEPOLIA_RPC_URL" --broadcast --verify --etherscan-api-key "$ETHERSCAN_API_KEY" -vv
```

Record `CCIPSender` in `ARBITRUM_CCIP_SENDER`, then allowlist it on Ethereum Sepolia:

```sh
set -a; source .env; set +a
forge script script/ConfigureLane.s.sol:ConfigureLane --rpc-url "$ETH_SEPOLIA_RPC_URL" --broadcast -vv
```

After a report is published, configure the sender's report cutoff to the registry's `crossChainCutoff` before accepting remote deposits. The report publication requires an exact report/claim hash and a live reviewer approval signature. This repository does not forge that approval.

## 4. Yield market after a report locks

`YieldSplitter.lock(reportId)` must run after the report's `lockTime`; it creates the report-specific YT. Record `Splitter`, `Treasury`, and the `reportId` in `.env`. Then `DeployYieldHook` mines a CREATE2 salt for the exact v4 hook permission bits, deploys the hook through `YieldHookFactory`, initializes the v4 pool, and deploys the compatible `YieldSwapRouter`.

```sh
forge script script/DeployYieldHook.s.sol:DeployYieldHook --rpc-url "$ETH_SEPOLIA_RPC_URL" --broadcast --verify --etherscan-api-key "$ETHERSCAN_API_KEY" -vv
```

Record `YieldMarketHook` in `SEPOLIA_HOOK`. Fund the Treasury with **separate deployer-owned dUSD** and seed it with its issued YT:

```sh
set -a; source .env; set +a
forge script script/SeedPool.s.sol:SeedPool --rpc-url "$ETH_SEPOLIA_RPC_URL" --broadcast -vv
```

`LIQUIDITY_USD_AMOUNT` and `LIQUIDITY_YT_AMOUNT` are six-decimal base units. The first live swap must use `YieldSwapRouter`, which prepays input within the v4 unlock before the hook takes it. The usual swap-first router path is incompatible with this hook. Show an explorer transaction for a buy and sell, LP yield claim, and LP withdrawal after maturity before claiming the Uniswap prize integration is complete.

## 5. Evidence to export

For each chain, export verified contract addresses, deployment transaction hashes, explorer links, CCIP message ID and destination credit transaction, token-pool registry configuration, the v4 PoolKey/hook address and real swap transactions. `forge script --verify` submits source to the relevant explorer, but verify each address's explorer status and rerun `forge verify-contract` for any failure. Broadcast artifacts under `broadcast/` are Git-ignored; publish a reviewed `deployments/` JSON without keys.

The 30-day claim clock is real on Sepolia. Mock yield injection can simulate a short demonstration of accrued assets, but it does not shorten the claim maturity or prove real lending interest. World Agent Pass and IDKit backends, their secrets, and a real yield adapter remain separate deployment gates.
