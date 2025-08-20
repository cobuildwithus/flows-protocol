// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { FlowsTerminal } from "../src/juicebox/FlowsTerminal.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployFlowsTerminal is DeployScript {
    address public flowsTerminalImplementation;
    address public flowsTerminal;

    function deploy() internal override {
        address owner = vm.envAddress("INITIAL_OWNER");

        // Deploy the FlowsTerminal implementation
        FlowsTerminal implementation = new FlowsTerminal();
        flowsTerminalImplementation = address(implementation);

        // Deploy the ERC1967Proxy without initialization
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
        flowsTerminal = address(proxy);

        // Call initialize after proxy deployment
        FlowsTerminal(payable(flowsTerminal)).initialize(owner);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(
            filePath,
            string(abi.encodePacked("FlowsTerminalImpl: ", addressToString(flowsTerminalImplementation)))
        );
        vm.writeLine(filePath, string(abi.encodePacked("FlowsTerminal: ", addressToString(flowsTerminal))));
    }

    function getContractName() internal pure override returns (string memory) {
        return "FlowsTerminal";
    }
}
