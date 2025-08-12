// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { FlowTypes } from "../src/storage/FlowStorage.sol";
import { IFlow, ICustomFlow } from "../src/interfaces/IFlow.sol";
import { IChainalysisSanctionsList } from "../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";
import { CustomFlow } from "../src/flows/CustomFlow.sol";
import { Flow } from "../src/Flow.sol";
import { SingleAllocatorStrategy } from "../src/allocation-strategies/SingleAllocatorStrategy.sol";
import { IAllocationStrategy } from "../src/interfaces/IAllocationStrategy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title DeployCobuildFlow
/// @notice Deploys a standalone CustomFlow (Cobuild Flow) with a single top-level flow using SingleAllocatorStrategy with ROCKETMAN as allocator
contract DeployCobuildFlow is DeployScript {
    // Deployed contract addresses
    address public cobuildFlow;
    address public cobuildFlowImpl;

    string public contractName;

    // Track deployed SingleAllocatorStrategy addresses for logging
    address[] public singleAllocatorStrategies;

    // Allocator
    address internal constant ROCKETMAN = 0x289715fFBB2f4b482e2917D2f183FeAb564ec84F;

    function deploy() internal override {
        // ------------------------------------------------------------------
        // Env vars
        // ------------------------------------------------------------------
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address superToken = vm.envAddress("SUPER_TOKEN");
        uint32 baselinePoolFlowRatePercent = 0;
        uint32 managerRewardPoolFlowRatePercent = 0;
        uint32 bonusPoolQuorumBps = 1e6;
        address sanctionsOracle = vm.envAddress("SANCTIONS_ORACLE");
        contractName = "Cobuild";

        address connectPoolAdmin = 0x6eD3cec4ec39786094350FbCf10a6761B93f350d;

        // ------------------------------------------------------------------
        // Top-level strategy - SingleAllocatorStrategy with ROCKETMAN
        // ------------------------------------------------------------------
        IAllocationStrategy[] memory topStrategies = _singleAllocator(ROCKETMAN, initialOwner);

        // ------------------------------------------------------------------
        // Flow proxy using shared CustomFlow implementation
        // ------------------------------------------------------------------
        cobuildFlowImpl = _loadImplementation("CustomFlowImpl");

        bytes memory initData = abi.encodeCall(
            ICustomFlow.initialize,
            (
                initialOwner,
                superToken,
                cobuildFlowImpl,
                ROCKETMAN,
                address(0),
                address(0),
                connectPoolAdmin,
                IFlow.FlowParams({
                    baselinePoolFlowRatePercent: baselinePoolFlowRatePercent,
                    managerRewardPoolFlowRatePercent: managerRewardPoolFlowRatePercent,
                    bonusPoolQuorumBps: bonusPoolQuorumBps
                }),
                FlowTypes.RecipientMetadata({
                    title: unicode"Flows",
                    description: unicode"Our mission is to increase community driven impact in the world.",
                    image: "ipfs://QmWzuj5XWACjZmUG8uyc5ZCf2DYSXU4kdi1PNvAdpfUcdn",
                    tagline: "Helping you build what matters",
                    url: "https://flows.wtf"
                }),
                IChainalysisSanctionsList(sanctionsOracle),
                topStrategies
            )
        );

        cobuildFlow = address(new ERC1967Proxy(cobuildFlowImpl, initData));
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("CobuildFlowImpl: ", addressToString(cobuildFlowImpl))));
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(cobuildFlow))));
    }

    function getContractName() internal view override returns (string memory) {
        return contractName;
    }

    /// @dev Deploys a SingleAllocatorStrategy with the given allocator and returns it as a single-item array.
    function _singleAllocator(address allocator, address owner) internal returns (IAllocationStrategy[] memory arr) {
        address impl = _loadImplementation("SingleAllocatorStrategyImpl");

        bytes memory strategyInitData = abi.encodeCall(SingleAllocatorStrategy.initialize, (owner, allocator));

        address proxy = address(new ERC1967Proxy(impl, strategyInitData));

        singleAllocatorStrategies.push(proxy);
        arr = new IAllocationStrategy[](1);
        arr[0] = IAllocationStrategy(proxy);
    }
}
