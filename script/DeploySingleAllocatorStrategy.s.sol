// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { SingleAllocatorStrategy } from "../src/allocation-strategies/SingleAllocatorStrategy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title DeploySingleAllocatorStrategy
/// @notice Deploys a SingleAllocatorStrategy proxy using existing implementation and allocator from env
contract DeploySingleAllocatorStrategy is DeployScript {
    address public singleAllocatorStrategy;
    address public implementation;
    string public contractName;

    function deploy() internal override {
        // Load parameters from environment
        address owner = vm.envAddress("INITIAL_OWNER");
        address allocator = vm.envAddress("ALLOCATOR");

        // Load existing implementation from deployment file
        implementation = _loadImplementation("SingleAllocatorStrategyImpl");

        // Deploy proxy
        bytes memory initData = abi.encodeCall(SingleAllocatorStrategy.initialize, (owner, allocator));

        singleAllocatorStrategy = address(new ERC1967Proxy(implementation, initData));

        contractName = "SingleAllocatorStrategy.nickhaaz";
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(singleAllocatorStrategy))));
        vm.writeLine(filePath, string(abi.encodePacked("Strategy: ", addressToString(implementation))));
        vm.writeLine(
            filePath,
            string(
                abi.encodePacked(
                    "Allocator: ",
                    addressToString(SingleAllocatorStrategy(singleAllocatorStrategy).allocator())
                )
            )
        );
    }

    function getContractName() internal view override returns (string memory) {
        return contractName;
    }
}
