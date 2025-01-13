// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { ERC20VotesMintable } from "../src/ERC20VotesMintable.sol";

contract DeployERC20MintableUpgrade is DeployScript {
    address public mintableImplementation;

    function deploy() internal override {
        // Deploy new ERC20VotesMintable implementation
        ERC20VotesMintable mintableImpl = new ERC20VotesMintable();
        mintableImplementation = address(mintableImpl);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(
            filePath,
            string(abi.encodePacked("New ERC20VotesMintableImpl: ", addressToString(mintableImplementation)))
        );
    }

    function getContractName() internal pure override returns (string memory) {
        return "ERC20VotesMintable.Upgrade";
    }
}
