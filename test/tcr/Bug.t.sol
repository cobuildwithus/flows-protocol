// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { FlowTCRTest } from "./FlowTCR.t.sol";

import { NounsFlow } from "../../src/NounsFlow.sol";
import { Flow } from "../../src/Flow.sol";
import { ERC20VotesArbitrator } from "../../src/tcr/ERC20VotesArbitrator.sol";

contract TCRFundFlowTest is FlowTCRTest {
    function test_issue() public {
        vm.createSelectFork(vm.rpcUrl("base"));

        address arbitrator = address(0xb0EB99c30E9E0aCAB592b0F696E78E719543913F);

        address newImpl = address(new ERC20VotesArbitrator());

        ERC20VotesArbitrator(arbitrator).executeRuling(11);
    }
}
