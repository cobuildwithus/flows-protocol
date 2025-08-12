// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { FlowTCRTest } from "./FlowTCR.t.sol";
import { Flow } from "../../src/Flow.sol";
import { CustomFlow } from "../../src/flows/CustomFlow.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TCRFundFlowTest is FlowTCRTest {
    function test_storage_issue() public {
        // uint256 blockNumber = 138002442;
        vm.createSelectFork(vm.rpcUrl("optimism"));

        address gardensFlow = address(0x329A322e591D5B7B71d45d956607998D8d71C819);
        address childFlow = address(0x329A322e591D5B7B71d45d956607998D8d71C819);

        // address newImpl = address(new CustomFlow());

        // vm.startPrank(0x289715fFBB2f4b482e2917D2f183FeAb564ec84F);
        // Flow(gardensFlow).upgradeTo(newImpl);

        uint256 outOfSync = Flow(gardensFlow).childFlowRatesOutOfSync();

        assertEq(outOfSync, 1);

        Flow(gardensFlow).workOnChildFlowsToUpdate(1);

        assertEq(Flow(gardensFlow).childFlowRatesOutOfSync(), 0);
    }
}
