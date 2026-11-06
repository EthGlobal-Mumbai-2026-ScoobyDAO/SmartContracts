# V2 local end-to-end test

Run from the repository root:

```sh
forge test --match-path 'test/*V2.t.sol' --summary
forge test --match-path test/EightVoterWorkflowV2.t.sol -vv
```

The first command runs the **25 V2-only local tests** without a network RPC. The second focuses on the [eight-voter end-to-end test](test/EightVoterWorkflowV2.t.sol). No V1 contract or V1 test helper is imported by the V2 tests. [V2Mocks.sol](test/helpers/V2Mocks.sol) supplies the six-decimal demo tokens and a local router using Chainlink's CCIP message types. The router can wait before delivery and models a source-token burn plus destination-token mint. It does not prove live Chainlink delivery.

## Main workflow

1. A reviewer signs a report and the publisher registers it in `ReportRegistry`. The V2 vault initializes one report series and its YT token.
2. Carol stakes Yes and supplies dUSD/YT liquidity to the v4 hook. Alice deposits 81 dUSD and receives 81 REP, then burns 80 REP to stake Yes; 1 REP remains withdrawable. Other voters stake directly or use the atomic stake-and-sell router. Direct stakes internally mint and burn REP in the same transaction.
3. Heidi sends 5 source-chain demo dollars with `StakeIntentV2`. Before the simulated delivery she has no destination position. The mock router burns the source token, mints destination collateral, and calls `CCIPStakeReceiverV2`. The receiver deposits and burns REP, giving Heidi a Yes position and YT.
4. Across eight voters, the vault holds 145 dUSD of Yes positions and 75 dUSD of No positions. Its 221 dUSD balance includes 220 dUSD of staked principal and 1 dUSD backing Alice's idle REP. The test asserts the YT supply is 220.
5. Two simulated yield injections total 33 dUSD. YT holders and Carol's LP shares claim their accrued portions. Alice buys YT through the local v4 `PoolManager`; she cannot claim yield earned before her purchase. After the lock, a new stake with Alice's remaining REP reverts, while that REP remains withdrawable.
6. At maturity the resolver proposes No, a challenge is raised, and the adjudicator finalizes Yes. All eight position owners claim. The treasury receives 15 dUSD, or 20% of the 75 dUSD losing pool. The test checks principal and yield conservation within stated rounding bounds.
7. Carol exits LP after maturity. After the claim window, the sweep leaves the 1 dUSD backing Alice's idle REP untouched. Alice withdraws it; no collateral remains in the vault.

The same test file separately checks that Heidi can sell her CCIP-funded YT through v4 while keeping her verdict position. A late cross-chain delivery produces **REP for the source payer**, with no position or YT; after lock, the payer burns REP to withdraw the destination-chain collateral. [CCIPV2.t.sol](test/CCIPV2.t.sol) covers router authorization, replay protection, independent payer nonces, malformed messages, and the expired-message REP path. [RepReceiptV2.t.sol](test/RepReceiptV2.t.sol) covers REP transfer, withdrawal, and protection of idle REP collateral during loss and settlement.

## External fork check

`test/V2LivePoolFork.t.sol` is a separate local EVM fork test against Ethereum Sepolia's deployed PoolManager. It needs `ETH_SEPOLIA_RPC_URL`; the 25-test local command above does not. The fork test passed using `https://sepolia.gateway.tenderly.co`. It broadcasts no transaction. The onchain deployment and CCIP source message are recorded in [v2-testnets.json](deployments/v2-testnets.json); the live CCIP destination result must be checked separately.
