// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { CobuildSwapBaseFork_DeployProxy_Test } from "./CobuildSwap.t.sol";
import { CobuildSwap } from "../../src/experimental/CobuildSwap.sol";
import { ICobuildSwap } from "../../src/experimental/interfaces/ICobuildSwap.sol";

contract CobuildSwapBaseFork_Admin_Test is CobuildSwapBaseFork_DeployProxy_Test {
    function test_setJuiceboxAddresses_updatesStateAndEmits() public {
        address newDirectory = makeAddr("jbDirectory");
        address newTokens = makeAddr("jbTokens");

        vm.expectEmit(true, true, false, false, address(cs));
        emit ICobuildSwap.JuiceboxAddressesUpdated(newDirectory, newTokens);

        cs.setJuiceboxAddresses(newDirectory, newTokens);

        assertEq(address(cs.JB_DIRECTORY()), newDirectory, "directory not updated");
        assertEq(address(cs.JB_TOKENS()), newTokens, "tokens not updated");
    }

    function test_setJuiceboxAddresses_onlyOwner() public {
        address caller = makeAddr("notOwner");
        address newDirectory = makeAddr("dirNonOwner");
        address newTokens = makeAddr("tokensNonOwner");

        vm.expectRevert();
        vm.prank(caller);
        cs.setJuiceboxAddresses(newDirectory, newTokens);
    }

    function test_setJuiceboxAddresses_zeroAddressReverts() public {
        address validDirectory = makeAddr("validDir");
        address validTokens = makeAddr("validTokens");

        vm.expectRevert(ICobuildSwap.ZERO_ADDR.selector);
        cs.setJuiceboxAddresses(address(0), validTokens);

        vm.expectRevert(ICobuildSwap.ZERO_ADDR.selector);
        cs.setJuiceboxAddresses(validDirectory, address(0));
    }
}
