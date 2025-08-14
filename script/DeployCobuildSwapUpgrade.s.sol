// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { CobuildSwap } from "../src/experimental/CobuildSwap.sol";

/// @title DeployCobuildSwapUpgrade
/// @notice Deploys a new CobuildSwap implementation for a proxy upgrade
contract DeployCobuildSwapUpgrade is DeployScript {
    address public cobuildSwapImplementation;

    function deploy() internal override {
        CobuildSwap impl = new CobuildSwap();
        cobuildSwapImplementation = address(impl);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(
            filePath,
            string(abi.encodePacked("New CobuildSwapImpl: ", addressToString(cobuildSwapImplementation)))
        );
    }

    function getContractName() internal pure override returns (string memory) {
        return "CobuildSwap.Upgrade";
    }
}
