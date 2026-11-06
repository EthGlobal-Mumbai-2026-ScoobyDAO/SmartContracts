# RiskFi PT/YT V2 review

This is a new, **local-only** implementation of the staker-owned yield design in the supplied build guide. No V2 transaction has been broadcast. The verified V1 Sepolia contracts remain unchanged.

## Behavior

- [`RiskFiStakeVaultV2`](src/v2/RiskFiStakeVaultV2.sol) creates one reviewed report series. A stake records a non-transferable, side-specific verdict position and mints the same notional amount of YT to the chosen receiver immediately. The staker can keep YT or direct it to the atomic router for sale. A winner claims principal plus 80% of the losing pool, the treasury receives 20% of the losing pool, and Void refunds principal. Principal loss scales payouts pro rata.
- [`StakerYieldToken`](src/v2/StakerYieldToken.sol) tracks a global yield index. Minting and transfers checkpoint balances so a later staker or buyer cannot claim earlier yield. Yield is paid independently of the report verdict.
- [`YieldCurveHookV2`](src/v2/YieldCurveHookV2.sol) owns YT/dUSD reserves and uses Uniswap v4 PoolManager for custom-accounting swaps. Its implied rate is `anchorRateWad + slopeWadPerUnit * netYTBought`, bounded by the configured minimum and maximum. Marginal YT price multiplies that rate by remaining years until maturity. `quoteBuy` and `quoteSell` use the same calculations as swaps. Quotes can become unavailable before maturity when a six-decimal payout rounds to zero or inventory/rate bounds are reached. The hook attributes YT income earned in its inventory to explicit LP shares.
- [`YieldCurveFactoryV2`](src/v2/YieldCurveFactoryV2.sol) requires the mined v4 permission bits and initializes the pool. [`StakeAndSellRouterV2`](src/v2/StakeAndSellRouterV2.sol) stakes dUSD, mints YT to itself, sells YT through the v4 router, and pays dUSD proceeds to the staker in one transaction. A failed swap reverts the entire stake.
- [`CCIPStakeSenderV2`](src/v2/CCIPStakeSenderV2.sol) sends funded `StakeIntentV2` messages through Chainlink's `IRouterClient` from Arbitrum Sepolia. [`CCIPStakeReceiverV2`](src/v2/CCIPStakeReceiverV2.sol) accepts only the configured router, chain, sender, and dUSD token, then credits a V2 position and mints staker-owned YT on Ethereum Sepolia. Each source payer has an independent nonce. Invalid or late deliveries stay recoverable by the source payer; malformed messages require the designated recovery operator.

## Regression evidence

Run `set -a; source .env; set +a; forge test --summary` to include live fork checks. At review time, 37 tests passed and none failed. The V2-specific tests cover late mint and transfer accrual, Void and challenged verdicts, principal loss, quote/swap equality, 256 fuzzed buy/sell round trips, time decay without trades, rate bounds, maturity gates, slippage rollback, atomic stake/sell/claim, mined hook deployment, and buy/sell against Sepolia's actual PoolManager in a **local fork**. `forge fmt --check` and `forge build` are separate gates.

[`EightVoterWorkflowV2.t.sol`](test/EightVoterWorkflowV2.t.sol) follows eight funded voters from signed report publication through five Yes and three No stakes (145/75 dUSD). Heidi's vote arrives through a mock CCIP router and gives her a V2 position and YT; a separate test sells her delivered YT through the v4 pool. Bob and Eve sell their newly minted YT during staking; Carol seeds the v4 pool with her YT and separate dUSD; Alice later buys YT. Two simulated yield periods distribute 33 dUSD to current YT holders and Carol's LP shares. A challenged No proposal is adjudicated Yes after maturity. All eight verdict positions are claimed, the treasury receives 15 dUSD from the losing pool, Carol exits LP after maturity, and principal rounding dust is swept after the claim window. The test accounts for every dUSD unit, including at most two base units of LP index rounding dust retained by the hook.

[`CCIPV2.t.sol`](test/CCIPV2.t.sol) checks independently reusable payer nonces, router-only delivery, replay rejection, wrong-chain rejection, late-fund recovery by the source payer, and operator recovery for malformed messages. These are local mock-router tests. [`PreflightSourceV2.s.sol`](script/PreflightSourceV2.s.sol) makes a read-only live router fee quote for the V2 token-plus-data message shape; it sends no CCIP message.

The read-only Arbitrum Sepolia preflight returned a live quote of 2,001,988,491,940,296 wei for one dUSD and the V2 intent payload on the Ethereum Sepolia lane. The quote changes with network conditions and does not prove delivery. Deployment scripts are prepared as [`DeployV2Sepolia.s.sol`](script/DeployV2Sepolia.s.sol), [`DeployV2Source.s.sol`](script/DeployV2Source.s.sol), and [`ConfigureV2Lane.s.sol`](script/ConfigureV2Lane.s.sol). The sequence after review is destination vault and receiver, source sender, receiver allowlist, report publication and series initialization, then a configured source cutoff. No script has been broadcast.

[`CCIP.t.sol`](test/CCIP.t.sol) also runs an eight-voter V1 integration: one mock-router CCIP-funded vote and seven local votes, followed by vault lock, YT yield, verdict settlement, treasury fee, a signed REP authorization, and principal conservation. This is a local CCIP simulation; it is not a live cross-chain delivery and does not credit a V2 position.

## Boundaries for review

- The vault uses **simulated yield injection** over DemoUSD. It is not an ERC-4626 lending integration, and DemoUSD is not Circle USDC.
- One V2 vault and YT series serves one report. Fungible YT across multiple reports sharing a maturity needs a separate bucket design and index-normalized accounting.
- V2 stakes and their Yes/No sides are public onchain. The non-transferable verdict position prevents secondary trading; it does not provide stake privacy.
- V2 CCIP contracts are implemented and tested locally but are not deployed. Existing deployed V1 CCIP contracts are tied to the V1 market and cannot credit a V2 position. There is no live V2 delivery evidence or World backend yet.
- The hook and atomic router are not deployed on Sepolia. The fork test executes only in local EVM state. A live swap, frontend flow, and end-to-end prize evidence remain pending.
- The curve is a bounded market price mechanism, not an oracle for future yield or the report verdict. Formal security review, adversarial testing, and real-yield liquidity design are still required before non-demo funds.

**Deployment is paused at the user's request for review.**
