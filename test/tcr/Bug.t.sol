// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { FlowTCRTest } from "./FlowTCR.t.sol";

import { NounsFlow } from "../../src/flows/NounsFlow.sol";
import { Flow } from "../../src/Flow.sol";

contract TCRFundFlowTest is FlowTCRTest {
    function test_storage_issue() public {
        uint256 blockNumber = 28156695;
        vm.createSelectFork(vm.rpcUrl("base"), blockNumber);

        address deployedFlow = address(0x0D4a25d07015ec7BdebF78f2937A617A86AF27Ff);

        address softwareFlow = address(0x03bBF8812B0635774Bdf344C0DE33d94a057aA28);

        address nounsFlowImpl = address(new NounsFlow());
    }
}
