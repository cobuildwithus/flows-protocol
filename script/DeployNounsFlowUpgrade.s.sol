// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { NounsFlow } from "../src/flows/NounsFlow.sol";

contract DeployNounsFlowUpgrade is DeployScript {
    address public nounsFlowImplementation;

    function deploy() internal override {
        // Deploy new NounsFlow implementation
        NounsFlow nounsFlowImpl = new NounsFlow();
        nounsFlowImplementation = address(nounsFlowImpl);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(
            filePath,
            string(abi.encodePacked("New NounsFlowImpl: ", addressToString(nounsFlowImplementation)))
        );
    }

    function getContractName() internal pure override returns (string memory) {
        return "NounsFlow.Upgrade";
    }
}
