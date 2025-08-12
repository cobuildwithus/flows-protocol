// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { BulkPoolWithdraw } from "../src/macros/BulkPoolWithdraw.sol";

/// @title DeployBulkPoolWithdraw
/// @notice Deploys the BulkPoolWithdraw macro contract and records its address.
contract DeployBulkPoolWithdraw is DeployScript {
    address public bulkPoolWithdraw;

    function deploy() internal override {
        BulkPoolWithdraw macroContract = new BulkPoolWithdraw();
        bulkPoolWithdraw = address(macroContract);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("BulkPoolWithdraw: ", addressToString(bulkPoolWithdraw))));
    }

    function getContractName() internal pure override returns (string memory) {
        return "BulkPoolWithdraw";
    }
}
