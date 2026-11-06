// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "../src/Utils.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";
import {CCIPStakeReceiverV2} from "../src/v2/CCIPStakeReceiverV2.sol";
import {CCIPStakeSenderV2} from "../src/v2/CCIPStakeSenderV2.sol";
import {StakerYieldToken} from "../src/v2/StakerYieldToken.sol";
import {YieldCurveHookV2} from "../src/v2/YieldCurveHookV2.sol";

/// @notice Reads deployed V2 state; warps only the local fork for the 30-day settlement phase.
contract V2DeployedForkTest is Test {
    address constant WALLET = 0xd561d3e95a02fDD8DbC94d15BFBF1b1634234b3a;
    bytes32 constant MESSAGE_ID = 0xaed819aad1fde53644aa058481a0f606f0ae2e9f78a9bbf2a3264e8c4db1456d;

    function testDeployedSepoliaV2WiringAndFutureSettlement() public {
        string memory rpc = vm.envOr("ETH_SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        RiskFiStakeVaultV2 vault = RiskFiStakeVaultV2(vm.envAddress("SEPOLIA_V2_VAULT"));
        CCIPStakeReceiverV2 receiver = CCIPStakeReceiverV2(vm.envAddress("SEPOLIA_V2_CCIP_RECEIVER"));
        YieldCurveHookV2 hook = YieldCurveHookV2(vm.envAddress("SEPOLIA_V2_HOOK"));
        StakerYieldToken yt = vault.yt();
        IERC20 usd = vault.usdc();
        assertEq(vault.reportId(), 1);
        assertEq(address(receiver.vault()), address(vault));
        assertEq(receiver.sourceSender(), vm.envAddress("ARBITRUM_V2_CCIP_SENDER"));
        assertEq(address(hook.yt()), address(yt));
        assertEq(vault.positionOf(WALLET, true), 100_000_000);
        assertTrue(receiver.delivered(MESSAGE_ID), "live CCIP message must be delivered");
        assertEq(vault.positionOf(WALLET, false), 15_000_000);
        assertGe(yt.balanceOf(WALLET), 5_000_000);
        assertGt(hook.ytReserve(), 0);
        uint256 totalNo = vault.totalNo();
        uint256 principal = vault.totalYes() + totalNo;
        assertEq(usd.balanceOf(address(vault)), principal);
        assertEq(vault.rep().totalSupply(), 0);

        vm.prank(WALLET);
        usd.approve(address(vault), 10_000_000);
        vm.prank(WALLET);
        vault.injectYield(10_000_000);
        vm.prank(WALLET);
        uint256 lpYield = hook.claimLPYield();
        assertGt(lpYield, 0);

        vm.warp(vault.maturity());
        vm.prank(WALLET);
        vault.propose(RiskFiStakeVaultV2.Outcome.No, keccak256("initial evidence"));
        vm.prank(WALLET);
        vault.challenge(keccak256("counter evidence"));
        vm.prank(WALLET);
        vault.adjudicate(RiskFiStakeVaultV2.Outcome.Yes, keccak256("adjudicated evidence"));
        assertEq(uint256(vault.finalOutcome()), uint256(RiskFiStakeVaultV2.Outcome.Yes));
        vm.prank(WALLET);
        uint256 winnerPaid = vault.claimPrincipal(true, 100_000_000);
        vm.prank(WALLET);
        assertEq(vault.claimPrincipal(false, totalNo), 0);
        uint256 fee = vault.claimFee();
        assertEq(winnerPaid, 100_000_000 + totalNo - totalNo / 5);
        assertEq(fee, totalNo / 5);
        assertEq(winnerPaid + fee, principal);
        assertEq(usd.balanceOf(address(vault)), 0);
        uint256 lpShares = hook.shares().balanceOf(WALLET);
        vm.prank(WALLET);
        hook.removeLiquidity(lpShares, 0, 0);
    }

    function testDeployedArbitrumV2SourceSentFundedMessage() public {
        string memory rpc = vm.envOr("ARB_SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        CCIPStakeSenderV2 sender = CCIPStakeSenderV2(vm.envAddress("ARBITRUM_V2_CCIP_SENDER"));
        assertEq(sender.owner(), WALLET);
        assertEq(sender.destinationReceiver(), vm.envAddress("SEPOLIA_V2_CCIP_RECEIVER"));
        assertGt(sender.reportCutoff(1), block.timestamp);
        assertTrue(sender.usedNonce(WALLET, 1), "source send consumed nonce");
    }
}
