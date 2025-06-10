// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { ERC721VotingStrategy } from "../src/allocation-strategies/ERC721VotingStrategy.sol";

/// @title DeployERC721VotingStrategyImpl
/// @notice Deploys the ERC721VotingStrategy implementation contract (no proxy) and records its address.
contract DeployERC721VotingStrategyImpl is DeployScript {
    address public implementation;
    string public contractName;

    function deploy() internal override {
        ERC721VotingStrategy impl = new ERC721VotingStrategy();
        implementation = address(impl);
        contractName = "ERC721VotingStrategyImpl";
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(implementation))));
    }

    function getContractName() internal view override returns (string memory) {
        return contractName;
    }
}
