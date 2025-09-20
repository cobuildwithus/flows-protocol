// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { ERC721VotesStrategy } from "../src/allocation-strategies/ERC721VotesStrategy.sol";

/// @title DeployERC721VotesStrategyImpl
/// @notice Deploys the ERC721VotesStrategy implementation contract (no proxy) and records its address.
contract DeployERC721VotesStrategyImpl is DeployScript {
    address public implementation;
    string public contractName;

    function deploy() internal override {
        ERC721VotesStrategy impl = new ERC721VotesStrategy();
        implementation = address(impl);
        contractName = "ERC721VotesStrategyImpl";
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(implementation))));
    }

    function getContractName() internal view override returns (string memory) {
        return contractName;
    }
}
