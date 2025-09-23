// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { FlowDeployer } from "../src/FlowDeployer.sol";

/// @title DeployFlowDeployerUpgrade
/// @notice Deploys a new `FlowDeployer` implementation for proxy upgrades
contract DeployFlowDeployerUpgrade is DeployScript {
    address public flowDeployerImplementation;

    function deploy() internal override {
        FlowDeployer impl = new FlowDeployer();
        flowDeployerImplementation = address(impl);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(
            filePath,
            string(abi.encodePacked("New FlowDeployerImpl: ", addressToString(flowDeployerImplementation)))
        );
    }

    function getContractName() internal pure override returns (string memory) {
        return "FlowDeployer.Upgrade";
    }
}
