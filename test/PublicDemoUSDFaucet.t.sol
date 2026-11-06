// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DemoUSD} from "../src/DemoUSD.sol";
import {IMintableDemoUSD, PublicDemoUSDFaucet} from "../src/v2/PublicDemoUSDFaucet.sol";

contract PublicDemoUSDFaucetTest is Test {
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    DemoUSD token;
    PublicDemoUSDFaucet faucet;

    function setUp() public {
        token = new DemoUSD();
        faucet = new PublicDemoUSDFaucet(IMintableDemoUSD(address(token)), 100_000_000, 60);
    }

    function testAnyoneCanClaimExistingTokenAfterRoleGrant() public {
        vm.expectRevert();
        vm.prank(ALICE);
        faucet.claim();
        token.grantRole(token.MINTER_ROLE(), address(faucet));
        vm.prank(ALICE);
        faucet.claim();
        assertEq(token.balanceOf(ALICE), 100_000_000);
        assertEq(faucet.nextClaimAt(ALICE), block.timestamp + 60);
        vm.prank(BOB);
        faucet.claim();
        assertEq(token.balanceOf(BOB), 100_000_000);
        vm.expectRevert(bytes("COOLDOWN"));
        vm.prank(ALICE);
        faucet.claim();
        vm.warp(block.timestamp + 60);
        vm.prank(ALICE);
        faucet.claim();
        assertEq(token.balanceOf(ALICE), 200_000_000);
        assertEq(token.balanceOf(BOB), 100_000_000);
    }

    function testAdminCanRevokeFaucetWithoutChangingToken() public {
        token.grantRole(token.MINTER_ROLE(), address(faucet));
        token.revokeRole(token.MINTER_ROLE(), address(faucet));
        vm.expectRevert();
        vm.prank(ALICE);
        faucet.claim();
        assertEq(faucet.lastClaimAt(ALICE), 0);
    }
}
