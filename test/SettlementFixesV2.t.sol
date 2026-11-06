// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {V2MockUSD} from "./helpers/V2Mocks.sol";
import {ReportRegistry} from "../src/ReportRegistry.sol";
import {RiskFiStakeVaultV2} from "../src/v2/RiskFiStakeVaultV2.sol";

/// @notice Regression tests for settlement timing, challenge visibility and series initialization.
contract SettlementFixesV2Test is Test {
    event Challenged(address indexed challenger, bytes32 evidenceHash);

    uint256 constant REVIEWER_KEY = 0xA11CE;
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant TREASURY = address(0x7EA5);
    V2MockUSD usdc;
    ReportRegistry registry;
    RiskFiStakeVaultV2 vault;
    uint256 reportId;
    uint64 lockTime;
    uint64 resultDeadline;

    function setUp() public {
        usdc = new V2MockUSD();
        registry = new ReportRegistry(address(this));
        vault = new RiskFiStakeVaultV2(usdc, registry, address(this), TREASURY);
        reportId = _publish(1);
        vault.initializeSeries(reportId);
        _stake(ALICE, true, 80_000_000);
        _stake(BOB, false, 20_000_000);
    }

    function _publish(uint256 nonce) internal returns (uint256 id) {
        lockTime = uint64(block.timestamp + 2 days);
        resultDeadline = uint64(uint256(lockTime) + 33 days);
        ReportRegistry.Report memory r = ReportRegistry.Report({
            reportHash: keccak256(abi.encode("settlement report", nonce)),
            claimHash: keccak256("settlement claim"),
            reviewer: vm.addr(REVIEWER_KEY),
            resolver: address(this),
            adjudicator: address(this),
            lockTime: lockTime,
            crossChainCutoff: uint64(lockTime - 1 days),
            resultDeadline: resultDeadline,
            challengePeriod: 1 days
        });
        uint64 expiry = uint64(block.timestamp + 1 days);
        (uint8 v, bytes32 a, bytes32 b) = vm.sign(REVIEWER_KEY, registry.approvalDigest(r, nonce, expiry));
        id = registry.publish(r, nonce, expiry, abi.encodePacked(a, b, v));
    }

    function _stake(address who, bool yes, uint256 amount) internal {
        usdc.mint(who, amount);
        vm.startPrank(who);
        usdc.approve(address(vault), amount);
        vault.stake(reportId, yes, amount, who, who);
        vm.stopPrank();
    }

    /// Previously any finalize() after resultDeadline returned Void, discarding an unchallenged verdict.
    function testLateFinalizeKeepsUnchallengedVerdict() public {
        vm.warp(vault.maturity());
        vault.propose(RiskFiStakeVaultV2.Outcome.Yes, keccak256("evidence"));
        vm.warp(uint256(resultDeadline) + 10 days);
        vault.finalize();
        assertEq(uint256(vault.finalOutcome()), uint256(RiskFiStakeVaultV2.Outcome.Yes));
        vm.prank(ALICE);
        assertEq(vault.claimPrincipal(true, 80_000_000), 96_000_000, "80 + 80% of 20");
    }

    /// A proposal made close to the deadline still gets its full challenge period, then settles.
    function testProposalNearDeadlineSettlesAfterChallengeWindow() public {
        vm.warp(uint256(resultDeadline) - 1 hours);
        vault.propose(RiskFiStakeVaultV2.Outcome.No, keccak256("late evidence"));
        vm.warp(uint256(resultDeadline) + 1);
        vm.expectRevert(bytes("PENDING"));
        vault.finalize(); // challenge window still open: neither proposed nor Void yet
        vm.warp(uint256(vault.proposedAt()) + 1 days);
        vault.finalize();
        assertEq(uint256(vault.finalOutcome()), uint256(RiskFiStakeVaultV2.Outcome.No));
    }

    function testNoProposalVoidsOnlyAfterDeadline() public {
        vm.warp(resultDeadline);
        vm.expectRevert(bytes("PENDING"));
        vault.finalize();
        vm.warp(uint256(resultDeadline) + 1);
        vault.finalize();
        assertEq(uint256(vault.finalOutcome()), uint256(RiskFiStakeVaultV2.Outcome.Void));
        vm.prank(BOB);
        assertEq(vault.claimPrincipal(false, 20_000_000), 20_000_000, "Void refunds principal");
    }

    function testChallengeEmitsAndUnresolvedChallengeVoidsAfterDeadline() public {
        vm.warp(vault.maturity());
        vault.propose(RiskFiStakeVaultV2.Outcome.Yes, keccak256("evidence"));
        vm.expectEmit(true, false, false, true, address(vault));
        emit Challenged(BOB, keccak256("counterevidence"));
        vm.prank(BOB);
        vault.challenge(keccak256("counterevidence"));
        vm.warp(uint256(vault.proposedAt()) + 2 days);
        vm.expectRevert(bytes("PENDING"));
        vault.finalize(); // challenged: waits for the adjudicator until the deadline
        vm.warp(uint256(resultDeadline) + 1);
        vault.finalize();
        assertEq(uint256(vault.finalOutcome()), uint256(RiskFiStakeVaultV2.Outcome.Void));
    }

    function testOnlyAdminInitializesSeries() public {
        RiskFiStakeVaultV2 fresh = new RiskFiStakeVaultV2(usdc, registry, address(this), TREASURY);
        uint256 id = _publish(2);
        vm.prank(ALICE);
        vm.expectRevert(bytes("ADMIN"));
        fresh.initializeSeries(id);
        fresh.initializeSeries(id);
        assertEq(fresh.reportId(), id);
    }
}
