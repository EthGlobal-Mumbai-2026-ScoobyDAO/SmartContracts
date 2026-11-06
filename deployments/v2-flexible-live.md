# Accelerated V2 demo on testnets

This is a synthetic report for the one-hour demo. It is separate from the earlier V2 report and is not linked to a backend case or World ID approval. The frontend keeps both at `/accelerated` and `/onchain/1`.

The authoritative contract addresses, pool key, roles, and report hashes are in [`handoff/v2-flexible/addresses.json`](../handoff/v2-flexible/addresses.json).

- Ethereum Sepolia flexible registry: [`0xe983eb98b00e9c26179202b69393d97981794447`](https://sepolia.etherscan.io/address/0xe983eb98b00e9c26179202b69393d97981794447)
- Ethereum Sepolia vault: [`0x152ba69f4603c22b5f15c87fc6b25fcb7d5bb2e7`](https://sepolia.etherscan.io/address/0x152ba69f4603c22b5f15c87fc6b25fcb7d5bb2e7)
- Ethereum Sepolia Uniswap v4 YT hook: [`0xB0C529B3E0FD8dBbe460a80654F3C2eab2632a88`](https://sepolia.etherscan.io/address/0xB0C529B3E0FD8dBbe460a80654F3C2eab2632a88)
- Arbitrum Sepolia CCIP sender: [`0x41afd00b58646319028a1ceec7149da17a34f60e`](https://sepolia.arbiscan.io/address/0x41afd00b58646319028a1ceec7149da17a34f60e)
- Ethereum Sepolia CCIP receiver: [`0xeb367823d9aaf02820e60a7d5846d32d67d34f2b`](https://sepolia.etherscan.io/address/0xeb367823d9aaf02820e60a7d5846d32d67d34f2b)

## Transactions and timing

1. The operator published report #1 in the flexible registry and initialized the new vault's YT. [Report publication](https://sepolia.etherscan.io/tx/0x63762cf38812d5b7ff5674263edf9f3db76346b5ea6e8a130d61c8fbd66293d4), [vault initialization](https://sepolia.etherscan.io/tx/0x3f6937096fab38408c155e35d898e98bdbbfb5f58e796b1fcbbc9ed82f04085a).
2. The operator configured the Arbitrum CCIP sender's report cutoff. [Arbitrum transaction](https://sepolia.arbiscan.io/tx/0x5f622ab3b8b69f67383068dda42bfff0146fd340e68844e19265630212c6ac12).
3. The operator deployed the YT/dUSD v4 market and seeded its inventory. [Market setup transactions](https://sepolia.etherscan.io/tx/0x82858d70f3dfb1dfc93ae9de521f127a5e2bdc0b9175b1cc9841fbcf8132a3de), [YT and dUSD seed](https://sepolia.etherscan.io/tx/0xf529ff8c8f8861e03f3499c69e0824c8a5a3fad1a6e9ef21726f5b605be4f414).
4. The operator also staked 10 dUSD on No, so both sides are represented and a non-Void settlement is possible. [Token approval](https://sepolia.etherscan.io/tx/0x372b252360da4baa8494ba5454e0abc387f6d9094819c0fc70a9c41ff9d4785b), [No stake](https://sepolia.etherscan.io/tx/0x6ceb6a2697a24eb634d3859128f6d27e53eb4f473aa464e1761dfcd81089d7e4).
5. A live Uniswap v4 router swap bought YT with 0.0001 dUSD. The tiny input reflects the short maturity rate curve and the pool's 100 YT inventory. [Token approval](https://sepolia.etherscan.io/tx/0x65562db0dc86acd5515fd342f852be4e5385996f7bfdf8a5118bbbbbd1732f56), [successful YT buy](https://sepolia.etherscan.io/tx/0x8716b8ebd18520ddad2d50e2e320d1f5f5067c9913ac37ffaaa214038743c65c).

The cross-chain cutoff is **2026-11-06 16:47:24 UTC**, the vote lock is **16:52:24 UTC**, market maturity is **17:32:24 UTC**, and the result deadline is **17:42:24 UTC**. After maturity, the resolver can propose a result; the challenge period is five minutes. Finalization and claims require subsequent onchain transactions. If no result is finalized before the deadline, `finalize()` yields Void. A delivered CCIP transfer for this new report has not yet been recorded.
