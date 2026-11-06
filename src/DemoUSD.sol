// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {BurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/BurnMintERC20.sol";

/// @notice Six-decimal faucet token for a CCIP demo. This is not Circle USDC.
contract DemoUSD is BurnMintERC20 {
    constructor() BurnMintERC20("RiskFi Demo Dollar", "dUSD", 6, 0, 0) {}
}
