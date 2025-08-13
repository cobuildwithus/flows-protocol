// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { CobuildSwap } from "../src/experimental/CobuildSwap.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title DeployCobuildSwap
/// @notice Deploys the CobuildSwap contract behind an ERC1967 proxy and initializes it
contract DeployCobuildSwap is DeployScript {
    address public cobuildSwap;
    address public cobuildSwapImpl;
    string public contractName;

    function deploy() internal override {
        address usdc = vm.envAddress("USDC");
        address universalRouter = vm.envAddress("UNIVERSAL_ROUTER");
        address executor = vm.envAddress("EXECUTOR");
        address feeCollector = vm.envAddress("FEE_COLLECTOR");
        uint16 feeBps = uint16(vm.envUint("FEE_BPS"));
        uint256 minFeeAbs = vm.envUint("MIN_FEE_ABS");

        contractName = "CobuildSwap";

        cobuildSwapImpl = address(new CobuildSwap());

        bytes memory initData = abi.encodeCall(
            CobuildSwap.initialize,
            (usdc, universalRouter, executor, feeCollector, feeBps, minFeeAbs)
        );

        cobuildSwap = address(new ERC1967Proxy(cobuildSwapImpl, initData));
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("CobuildSwapImpl: ", addressToString(cobuildSwapImpl))));
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(cobuildSwap))));
    }

    function getContractName() internal view override returns (string memory) {
        return contractName;
    }
}
