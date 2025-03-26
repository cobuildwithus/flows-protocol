// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { TCRFactory } from "../src/tcr/TCRFactory.sol";

contract DeployTCRFactoryUpgrade is DeployScript {
    address public tcrFactoryImplementation;

    function deploy() internal override {
        // Deploy new ERC20VotesArbitrator implementation
        TCRFactory tcrFactoryImpl = new TCRFactory();
        tcrFactoryImplementation = address(tcrFactoryImpl);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(
            filePath,
            string(abi.encodePacked("New TCRFactoryImpl: ", addressToString(tcrFactoryImplementation)))
        );
    }

    function getContractName() internal pure override returns (string memory) {
        return "TCRFactory.Upgrade";
    }
}
