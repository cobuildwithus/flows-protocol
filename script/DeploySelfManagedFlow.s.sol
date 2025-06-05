// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { SelfManagedFlow } from "../src/flows/SelfManagedFlow.sol";

contract DeploySelfManagedFlow is DeployScript {
    address public selfManagedFlowImplementation;

    function deploy() internal override {
        // Deploy new ERC20VotesArbitrator implementation
        SelfManagedFlow selfManagedFlowImpl = new SelfManagedFlow();
        selfManagedFlowImplementation = address(selfManagedFlowImpl);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(
            filePath,
            string(abi.encodePacked("New SelfManagedFlowImpl: ", addressToString(selfManagedFlowImplementation)))
        );
    }

    function getContractName() internal pure override returns (string memory) {
        return "SelfManagedFlow";
    }
}
