// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { FlowDeployer } from "../src/FlowDeployer.sol";
import { IResolver } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/utils/IResolver.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IChainalysisSanctionsList } from "../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";

/// @title DeployFlowDeployer
/// @notice Deploys the `FlowDeployer` helper contract
contract DeployFlowDeployer is DeployScript {
    address public flowDeployer;
    address public flowDeployerImpl;
    string public contractName;

    function deploy() internal override {
        // Env
        address resolver = vm.envAddress("SUPERFLUID_RESOLVER");
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address connectPoolAdmin = vm.envAddress("CONNECT_POOL_ADMIN");
        address managerRewardPool = vm.envAddress("MANAGER_REWARD_POOL");
        uint32 managerRewardPoolFlowRatePercent = uint32(vm.envUint("REWARDS_POOL_FLOW_RATE_PERCENT"));
        address sanctionsOracle = vm.envAddress("SANCTIONS_ORACLE");
        address customFlowImpl = _loadImplementation("CustomFlowImpl");
        address singleAllocatorStrategyImpl = _loadImplementation("SingleAllocatorStrategyImpl");

        contractName = "FlowDeployer";

        flowDeployerImpl = address(new FlowDeployer());

        bytes memory initData = abi.encodeCall(
            FlowDeployer.initialize,
            (
                IResolver(resolver),
                customFlowImpl,
                singleAllocatorStrategyImpl,
                initialOwner,
                connectPoolAdmin,
                managerRewardPool,
                managerRewardPoolFlowRatePercent,
                IChainalysisSanctionsList(sanctionsOracle)
            )
        );

        flowDeployer = address(new ERC1967Proxy(flowDeployerImpl, initData));
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("FlowDeployerImpl: ", addressToString(flowDeployerImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("FlowDeployer: ", addressToString(flowDeployer))));
    }

    function getContractName() internal view override returns (string memory) {
        return contractName;
    }
}
