// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { FlowTCR } from "../src/tcr/FlowTCR.sol";

contract DeployFlowTCRUpgrade is DeployScript {
    address public flowTCR;

    function deploy() internal override {
        // Deploy new ERC20VotesMintable implementation
        FlowTCR flowTCRImpl = new FlowTCR();
        flowTCR = address(flowTCRImpl);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("New FlowTCR: ", addressToString(flowTCR))));
    }

    function getContractName() internal pure override returns (string memory) {
        return "FlowTCR.Upgrade";
    }
}
