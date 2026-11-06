# V2 transactions, explained one by one

This document follows the **live V2 demo**. Ethereum Sepolia hosts the report, vault, Uniswap v4 YT market, and CCIP receiver. Arbitrum Sepolia hosts the CCIP sender. The wallet is `0xd561d3e95a02fDD8DbC94d15BFBF1b1634234b3a`. **dUSD** is our six-decimal demo token, not Circle USDC. ETH pays transaction gas and the CCIP fee; the cross-chain asset is dUSD. Contract addresses are in [v2-testnets.json](deployments/v2-testnets.json).

Each linked transaction has two points: **what happened** and **why it matters**. Approvals and token-admin role grants are setup transactions; this list focuses on the actions that show the V2 workflow. The final verdict is a local fork simulation because the live report has not matured.

## 1. Prepare dUSD for CCIP on both chains

### 1. Deploy dUSD on Ethereum Sepolia

[Transaction](https://sepolia.etherscan.io/tx/0xeda54cca80cd8adfb5fddd41e74d2c29b60876c9da18a72507e2e43719a86a1c)

- **What happened:** A six-decimal DemoUSD ERC-20 was deployed on Ethereum Sepolia.
- **Why it matters:** This is the collateral token the V2 vault receives and the YT market trades against. It is a demo token, not actual USDC.

### 2. Deploy its Ethereum Sepolia BurnMintTokenPool

[Transaction](https://sepolia.etherscan.io/tx/0x5f65df42042d265c4de66a2e57c8232cad2b62d58496aabda7487b827b81625f)

- **What happened:** A Chainlink CCIP BurnMintTokenPool was deployed for the Sepolia dUSD token.
- **Why it matters:** CCIP needs a registered destination pool to mint dUSD when a valid cross-chain transfer arrives.

### 3. Deploy dUSD on Arbitrum Sepolia

[Transaction](https://sepolia.arbiscan.io/tx/0x15a67b0347304e07fbf7832f8b1706234eb12907fe48aed9c1926c975a6e6e46)

- **What happened:** A matching six-decimal DemoUSD token was deployed on the source chain.
- **Why it matters:** The sender spends this token when funding a cross-chain vote.

### 4. Deploy its Arbitrum Sepolia BurnMintTokenPool

[Transaction](https://sepolia.arbiscan.io/tx/0x49dff7a5232bec05a232aab99bec20de0ee8d55522d181a42c40ad810508dee7)

- **What happened:** A Chainlink CCIP BurnMintTokenPool was deployed for source-chain dUSD.
- **Why it matters:** The source pool burns the dUSD that CCIP transfers. The destination pool later mints the corresponding amount.

### 5. Configure the Sepolia pool's remote chain

[Transaction](https://sepolia.etherscan.io/tx/0x8681f2e037592f61067167b56f3b978a5785cdc7608769f67b7a2cf57e1cd62a)

- **What happened:** The Sepolia pool was given Arbitrum Sepolia's chain selector, remote token, and remote pool.
- **Why it matters:** The destination must recognize which source pool and token are allowed to deliver dUSD.

### 6. Configure the Arbitrum pool's remote chain

[Transaction](https://sepolia.arbiscan.io/tx/0xa633a00c1b1a32791db72e47e1e0883ea1960d37f3f05a2283cf61cdc9c7b03a)

- **What happened:** The Arbitrum pool was given Ethereum Sepolia's chain selector, remote token, and remote pool.
- **Why it matters:** This completes the token-pool relationship in the sending direction.

### 7. Activate the Sepolia pool in Chainlink's token registry

[Transaction](https://sepolia.etherscan.io/tx/0x5d8ed89470b15cb5856dd1c191d080d3589baca2aabdf81935587d45f8b5c3bb)

- **What happened:** The Ethereum Sepolia TokenAdminRegistry mapped dUSD to its BurnMintTokenPool.
- **Why it matters:** Chainlink's destination infrastructure can now find the correct pool for dUSD.

### 8. Activate the Arbitrum pool in Chainlink's token registry

[Transaction](https://sepolia.arbiscan.io/tx/0xad005662e01ceec7853ec5e1bcc83150d8c537e94b1af5c8cec3803767d0b917)

- **What happened:** The Arbitrum Sepolia TokenAdminRegistry mapped source dUSD to its BurnMintTokenPool.
- **Why it matters:** Chainlink's source router can use that pool for token-plus-data messages. These eight token steps are shared infrastructure reused by V2.

## 2. Deploy and configure V2

### 9. Deploy the report registry

[Transaction](https://sepolia.etherscan.io/tx/0x7a1df17d084990f3a437f712732e23cac66cbfa4f26cd1665923562cd9613db8)

- **What happened:** The V2 ReportRegistry was deployed on Ethereum Sepolia.
- **Why it matters:** It stores approved reports and their lock, cutoff, resolver, and challenge rules.

### 10. Deploy the vault and REP receipt

[Transaction](https://sepolia.etherscan.io/tx/0xd6cea49b62d2300cb87abb91d6ec84339886d5561fa53739bf02cb5673829927)

- **What happened:** RiskFiStakeVaultV2 was deployed; its constructor also created the REP collateral receipt.
- **Why it matters:** The vault holds dUSD, records Yes/No positions, and handles yield and settlement. REP represents deposited collateral before staking.

### 11. Deploy the CCIP receiver

[Transaction](https://sepolia.etherscan.io/tx/0xd5e4a61096543441b628abb701b185e1284e8b69bd2d62a0c79f8f032e584bba)

- **What happened:** CCIPStakeReceiverV2 was deployed on Ethereum Sepolia.
- **Why it matters:** It validates the Chainlink router, source chain, sender, and token before crediting a V2 vote.

### 12. Deploy the CCIP sender

[Transaction](https://sepolia.arbiscan.io/tx/0x45dc450447f96db6b4061aa304d79c6d473d8e372802e12cee1b99e266cfc7b0)

- **What happened:** CCIPStakeSenderV2 was deployed on Arbitrum Sepolia.
- **Why it matters:** It combines a funded dUSD transfer with the V2 vote instructions in one CCIP message.

### 13. Allowlist that sender at the destination

[Transaction](https://sepolia.etherscan.io/tx/0xb3a502e143c8eecb2bf939f8ffda57e56cfab087da39901f95a4abbd0de56330)

- **What happened:** The Sepolia receiver was configured to accept the deployed Arbitrum sender.
- **Why it matters:** A message from a different source application cannot create a V2 position through this receiver.

### 14. Publish report #1

[Transaction](https://sepolia.etherscan.io/tx/0x4ca1797532d3836d0942be6ac20d87052c6fe873d245009c7bb006671a3df1cd)

- **What happened:** A reviewer-signed report was published in ReportRegistry.
- **Why it matters:** Stakes can now refer to one approved Yes/No question. The report sets the lock and result deadlines.

### 15. Initialize the report's YT series

[Transaction](https://sepolia.etherscan.io/tx/0x83e066eb19dda2e30f54d3114a360ade498f53d87bd74e6ed38185c8c03f480f)

- **What happened:** The vault initialized report #1 and created its StakerYieldToken (YT).
- **Why it matters:** Each funded stake can now mint YT separately from its nontransferable verdict position.

### 16. Set the cross-chain voting cutoff

[Transaction](https://sepolia.arbiscan.io/tx/0x959948f9f24fd0945fb160c944c83f285e66a1e2cc06d411467fa19b1ea816ca)

- **What happened:** The Arbitrum sender was told when report #1 stops accepting cross-chain sends.
- **Why it matters:** It prevents starting a remote vote too near the Sepolia lock. The cutoff is **November 8, 2026, 07:44 UTC**; Sepolia's local stake lock is **November 9, 2026, 07:44 UTC**.

## 3. Create and exercise the YT market

### 17. Deploy the V2 curve factory

[Transaction](https://sepolia.etherscan.io/tx/0x8487e356278437e4c6d9ab4f8685fbe5db5e32dfc0b16cec18fd90c0b58a1802)

- **What happened:** YieldCurveFactoryV2 was deployed.
- **Why it matters:** It deploys the hook at an address with the permission bits required by Uniswap v4.

### 18. Deploy the hook and initialize its v4 pool

[Transaction](https://sepolia.etherscan.io/tx/0x61b15809af0f0af4af23e099afe327c76fc6c6c2afdf3b35c8c896798fa7808c)

- **What happened:** The factory deployed YieldCurveHookV2, created its RF-YLP share token, configured the dUSD/YT pool, and initialized it in the deployed v4 PoolManager.
- **Why it matters:** The hook supplies the time-aware YT price curve and custom-accounting swap behavior. Pool creation alone did not add trading inventory.

### 19. Deploy the swap router

[Transaction](https://sepolia.etherscan.io/tx/0xc85c657725fe7e0404854d08602331fc4adffae6bc7656af03c2ae4493089400)

- **What happened:** YieldSwapRouter was deployed.
- **Why it matters:** Traders use it to settle token input and execute swaps through the v4 PoolManager and hook.

### 20. Deploy the atomic stake-and-sell router

[Transaction](https://sepolia.etherscan.io/tx/0xc36c5f6000d0fdecb32f492c9518a36db268de164840a9ec0217569d5eeabb65)

- **What happened:** StakeAndSellRouterV2 was deployed and wired to the vault, hook, and swap router.
- **Why it matters:** A voter can stake dUSD and immediately sell newly minted YT in one transaction while keeping the Yes/No position.

### 21. Stake 100 dUSD on Yes

[Transaction](https://sepolia.etherscan.io/tx/0x011dd447c03c1ea8ff8025e72e30a1bef77eeec7299bc493911c60364262e0d0)

- **What happened:** The wallet deposited and staked **100 dUSD Yes**. The vault recorded its Yes position and minted **100 YT**.
- **Why it matters:** This creates both a funded verdict position and the yield rights used as the initial market inventory. The wallet keeps its Yes position after transferring YT.

### 22. Seed liquidity with 50 dUSD and 100 YT

[Transaction](https://sepolia.etherscan.io/tx/0x076b98e0b8a1aeb43ded81737de69bc09a2ea11830e6ec4466bd3850b82e493f)

- **What happened:** The wallet called `YieldCurveHookV2.addLiquidity(50_000_000, 100_000_000, 1)`. The hook received **50 dUSD and 100 YT** and minted **70.710678 RF-YLP shares** to the wallet.
- **Why it matters:** This gave the market inventory for later YT buys and sells. The hook owns the tokens; RF-YLP tracks the wallet's share of the reserves and the yield earned by YT held there. The deposit ratio does not set the curve's trading price.

### 23. Buy YT with dUSD

[Transaction](https://sepolia.etherscan.io/tx/0x5e1bf9e88d2cfe91752b076334058670ecdb874909ecd0663aa6678c9b737027)

- **What happened:** The wallet swapped **0.1 dUSD** for YT using YieldSwapRouter and the v4 PoolManager.
- **Why it matters:** This proves that a separate trader can acquire the future yield rights supplied in step 22. The hook quotes and settles the swap using its rate curve.

### 24. Sell YT back into the pool

[Transaction](https://sepolia.etherscan.io/tx/0xdb2a2da2e3097db60a3a334622ccb72ab9839b52bb284acb0e171a1f8dbbab25)

- **What happened:** The wallet sold the YT bought in step 23 back for dUSD.
- **Why it matters:** This tests the other side of the live v4 market. Trading fees and the curve can make the returned dUSD differ from the original 0.1 dUSD.

### 25. Stake 10 dUSD No and sell its YT atomically

[Transaction](https://sepolia.etherscan.io/tx/0x8f5e454b971a1b3a19a684b1ca47bcd1916250b706148329456292e8e7a0a63a)

- **What happened:** One call staked **10 dUSD No**, minted **10 YT** to the atomic router, sold that YT into the v4 pool, and sent the sale proceeds to the wallet.
- **Why it matters:** The voter kept the funded No verdict position while monetizing its future yield rights immediately.

## 4. Distribute the first demo yield period

### 26. Inject 10 dUSD of simulated yield

[Transaction](https://sepolia.etherscan.io/tx/0xe837d7ff95efc98d4921a7c3bdd2ad50d12b29c57bd862e21c8f4cef2176c9ec)

- **What happened:** The wallet supplied **10 dUSD** to the vault's YT yield accounting.
- **Why it matters:** It creates a visible demo yield period. This is simulated collateral income, not a live lending strategy.

### 27. Claim yield belonging to LP inventory

[Transaction](https://sepolia.etherscan.io/tx/0x7fc2d0effd7f918e72022f1f1f5bc485da7f5d7ca82802836751aead261e4568)

- **What happened:** The RF-YLP holder claimed **9.999977 dUSD** accrued by YT held in the hook.
- **Why it matters:** It demonstrates that YT yield in market inventory belongs to the LP-share owner, rather than disappearing into the pool.

### 28. Claim yield on directly held YT

[Transaction](https://sepolia.etherscan.io/tx/0x364ab559d495f4f72136c3e50932c58f3e11b9804cffd8dca8fd6462c4c1332c)

- **What happened:** The wallet claimed **0.000021 dUSD** on the small YT balance it held outside the hook.
- **Why it matters:** Direct YT holders claim independently of LPs. Two dUSD base units remained because of index rounding.

## 5. Send and deliver the cross-chain vote

### 29. Send 5 dUSD and a No vote through CCIP

[Arbitrum Sepolia transaction](https://sepolia.arbiscan.io/tx/0x4f4e9a9f44ce28fb65ca80c5ba19a6ccda56223156e6e90d33884ffc18a99de2) · [CCIP message tracker](https://ccip.chain.link/#/side-drawer/msg/0xaed819aad1fde53644aa058481a0f606f0ae2e9f78a9bbf2a3264e8c4db1456d)

- **What happened:** The wallet sent **5 dUSD** with a V2 **No** vote intent from Arbitrum Sepolia. The source BurnMintTokenPool burned the dUSD; native Arbitrum Sepolia ETH paid the CCIP fee.
- **Why it matters:** The message transfers funded collateral and vote instructions together. A successful send alone does not prove that the Sepolia position was credited.

### 30. Record the failed first delivery attempt

[Ethereum Sepolia transaction](https://sepolia.etherscan.io/tx/0x9e16a3dccbb9215668b02b55ab7391b4d775bda8bf9ac582a0cf66d199401ea0)

- **What happened:** Chainlink submitted the message at the destination, but its OffRamp recorded `FAILURE` with an empty-data `ReceiverError`.
- **Why it matters:** The receiver had not credited the vote. The empty error was consistent with insufficient receiver callback gas, so the message needed a higher-gas retry.

### 31. Retry and complete CCIP delivery

[Ethereum Sepolia transaction](https://sepolia.etherscan.io/tx/0x9402e5d2292c1e0f3862678fc8e86eec1d479013a5d0dd0c08a25ccc6f38b9b1) · [CCIP message tracker](https://ccip.chain.link/#/side-drawer/msg/0xaed819aad1fde53644aa058481a0f606f0ae2e9f78a9bbf2a3264e8c4db1456d)

- **What happened:** A manual retry used a **1,500,000 receiver callback gas override** and a **5,000,000 outer transaction gas limit**. CCIP recorded `SUCCESS`, and the receiver marked the message delivered.
- **Why it matters:** The destination minted **5 dUSD**, credited the wallet's No position from **10 to 15 dUSD**, and minted **5 YT**. The wallet's YT balance immediately after delivery was **5.000232 YT**. This transaction is the proof of destination credit.

## 6. Show that cross-chain YT receives later yield

### 32. Inject a second 10 dUSD demo yield period

[Transaction](https://sepolia.etherscan.io/tx/0x373def2303b31624062f066bcc7d1f9c64a038aa9c4519c66e15e79d93b103e4)

- **What happened:** After CCIP delivery, the wallet injected another **10 dUSD** of simulated yield.
- **Why it matters:** The newly minted cross-chain YT now participates. It did not collect yield from the earlier period, before it existed.

### 33. Claim the LP's share of the second yield period

[Transaction](https://sepolia.etherscan.io/tx/0xb89ea488c1067e47ac33f727b4b834124a33bebfce71852851813241b98b8374)

- **What happened:** The RF-YLP holder claimed **9.565196 dUSD** attributable to YT in the hook.
- **Why it matters:** The LP still earns on its YT inventory, while some yield now goes to the separately held CCIP-minted YT.

### 34. Claim yield on the CCIP-minted YT

[Transaction](https://sepolia.etherscan.io/tx/0x2ec3844e8ddfe4627488fadad6a3ab57dd8543125b936168ee96ec550d64039d)

- **What happened:** The wallet claimed **0.434802 dUSD** from directly held YT, including the **5 YT** created after CCIP delivery.
- **Why it matters:** The cross-chain vote produced both a funded No position and a separate yield right that earns only from subsequent yield periods.

## 7. Verdict and payout simulation

The live report matures **December 9, 2026, 07:44 UTC**. No live verdict, principal-claim, or LP-exit transaction exists yet. [`V2DeployedFork.t.sol`](test/V2DeployedFork.t.sol) reads the real deployed state, requires the CCIP message to be delivered, advances **only a local Sepolia fork** to maturity, and tests proposal, challenge, adjudication, principal claims, protocol fee, and LP exit. It broadcasts no testnet transaction. The full `forge test --summary` suite passed **29 tests**.

For contract-to-feature links, see [README.md](README.md). For the eight-voter local workflow, see [V2_E2E.md](V2_E2E.md).
