// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { RewardPool } from "../src/RewardPool.sol";

contract DeployRewardsPoolUpgrade is DeployScript {
    address public rewardsPoolImplementation;

    function deploy() internal override {
        // Deploy new ERC20VotesArbitrator implementation
        RewardPool rewardsPoolImpl = new RewardPool();
        rewardsPoolImplementation = address(rewardsPoolImpl);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(
            filePath,
            string(abi.encodePacked("New RewardPoolImpl: ", addressToString(rewardsPoolImplementation)))
        );
    }

    function getContractName() internal pure override returns (string memory) {
        return "RewardPool.Upgrade";
    }
}
