// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { FlowTCRTest } from "./FlowTCR.t.sol";

import { NounsFlow } from "../../src/NounsFlow.sol";
import { Flow } from "../../src/Flow.sol";

contract TCRFundFlowTest is FlowTCRTest {
    // add 4 items, vote and execute using requester

    function test_issue() public {
        uint256 blockNumber = 28122420;
        vm.createSelectFork(vm.rpcUrl("base"), blockNumber);

        address deployedFlow = address(0x03bBF8812B0635774Bdf344C0DE33d94a057aA28);

        address nounsFlowImpl = address(new NounsFlow());
        // upgrade flow to current implementation
        vm.prank(Flow(deployedFlow).owner());
        Flow(deployedFlow).upgradeTo(nounsFlowImpl);

        vm.prank(Flow(deployedFlow).owner());
        Flow(deployedFlow).reinitializeChildFlowSets();

        vm.prank(Flow(deployedFlow).owner());
        Flow(deployedFlow).setBonusPoolQuorum(50000);
    }
}
