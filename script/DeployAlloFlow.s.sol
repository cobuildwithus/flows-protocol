// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { AllocatorFlow } from "../src/AllocatorFlow.sol";

contract DeployAllocatorFlow is DeployScript {
    address public allocatorFlowImplementation;

    function deploy() internal override {
        // Deploy new ERC20VotesArbitrator implementation
        AllocatorFlow allocatorFlowImpl = new AllocatorFlow();
        allocatorFlowImplementation = address(allocatorFlowImpl);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(
            filePath,
            string(abi.encodePacked("New AllocatorFlowImpl: ", addressToString(allocatorFlowImplementation)))
        );
    }

    function getContractName() internal pure override returns (string memory) {
        return "AllocatorFlow";
    }
}
