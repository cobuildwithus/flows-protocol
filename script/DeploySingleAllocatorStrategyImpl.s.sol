// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { SingleAllocatorStrategy } from "../src/allocation-strategies/SingleAllocatorStrategy.sol";

/// @title DeploySingleAllocatorStrategyImpl
/// @notice Deploys the SingleAllocatorStrategy implementation contract (no proxy) and records its address.
contract DeploySingleAllocatorStrategyImpl is DeployScript {
    address public implementation;
    string public contractName;

    function deploy() internal override {
        SingleAllocatorStrategy impl = new SingleAllocatorStrategy();
        implementation = address(impl);
        contractName = "SingleAllocatorStrategyImpl";
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(implementation))));
    }

    function getContractName() internal view override returns (string memory) {
        return contractName;
    }
}
