// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { CustomFlow } from "../src/flows/CustomFlow.sol";

/// @title DeployCustomFlowImpl
/// @notice Deploys the CustomFlow implementation (logic) contract and records its address.
contract DeployCustomFlowImpl is DeployScript {
    address public implementation;
    string public contractName;

    function deploy() internal override {
        CustomFlow impl = new CustomFlow();
        implementation = address(impl);
        contractName = "CustomFlowImpl";
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(implementation))));
    }

    function getContractName() internal view override returns (string memory) {
        return contractName;
    }
}
