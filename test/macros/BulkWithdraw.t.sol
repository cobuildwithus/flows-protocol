// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { BulkPoolWithdraw } from "../../src/macros/BulkPoolWithdraw.sol";

import { ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { MacroForwarder, IUserDefinedMacro } from "@superfluid-finance/ethereum-contracts/contracts/utils/MacroForwarder.sol";

contract BulkWithdrawTest is Test {
    function test_bulkPoolWithdraw() public {
        vm.createSelectFork(vm.rpcUrl("base"), 21080872);

        address bulkPoolWithdraw = address(new BulkPoolWithdraw());

        // Setup test data
        address testUser = address(0x289715fFBB2f4b482e2917D2f183FeAb564ec84F);
        address baselinePoolAddr = address(0x77f56007DdC2fC682f5BC98E8EFABcBac915DB78);
        address bonusPoolAddr = address(0x33Fe9F9aED096C9828a565fFBd457F6EB0f13d7f);

        // Prepare params for BulkPoolWithdraw
        address[] memory poolAddresses = new address[](2);
        poolAddresses[0] = baselinePoolAddr;
        poolAddresses[1] = bonusPoolAddr;
        bytes memory params = abi.encode(poolAddresses);

        MacroForwarder forwarder = MacroForwarder(0xfD01285b9435bc45C243E5e7F978E288B2912de6);

        // Run macro through MacroForwarder
        vm.prank(testUser);
        bool success = forwarder.runMacro(IUserDefinedMacro(bulkPoolWithdraw), params);

        // Assert
        assertTrue(success, "Macro execution should succeed");
        (int256 baselineClaimable, ) = ISuperfluidPool(baselinePoolAddr).getClaimableNow(testUser);
        assertEq(baselineClaimable, 0, "Baseline pool should be emptied");

        (int256 bonusClaimable, ) = ISuperfluidPool(bonusPoolAddr).getClaimableNow(testUser);
        assertEq(bonusClaimable, 0, "Bonus pool should be emptied");
    }
}
