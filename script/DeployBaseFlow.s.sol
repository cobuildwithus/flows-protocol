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

/// @title DeployBaseFlow
/// @notice Deploys a standalone CustomFlow (Base Flow) with a single top-level flow using SingleAllocatorStrategy with ROCKETMAN as allocator
contract DeployBaseFlow is DeployScript {
    // Deployed contract addresses
    address public baseFlow;
    address public baseFlowImpl;

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
        contractName = "Base";

        address connectPoolAdmin = 0x6eD3cec4ec39786094350FbCf10a6761B93f350d;

        // ------------------------------------------------------------------
        // Top-level strategy - SingleAllocatorStrategy with ROCKETMAN
        // ------------------------------------------------------------------
        IAllocationStrategy[] memory topStrategies = _singleAllocator(ROCKETMAN, initialOwner);

        // ------------------------------------------------------------------
        // Flow proxy using shared CustomFlow implementation
        // ------------------------------------------------------------------
        baseFlowImpl = _loadImplementation("CustomFlowImpl");

        bytes memory initData = abi.encodeCall(
            ICustomFlow.initialize,
            (
                initialOwner,
                superToken,
                baseFlowImpl,
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
                    title: unicode"Base Batches",
                    description: unicode"The internet should belong to all of us. Right now, most of it is closed, owned by a few, and built to extract. We believe in something better: An open internet where value flows freely, and where what you create is yours to own, grow, and share. That’s why we’re building Base. A home for builders, creators, and anyone who wants to shape the future. A new foundation for a truly free global economy. This flow tracks the winners from Base Batches Demo Day 001, an incubator program to help onchain founders grow their startups.",
                    image: "ipfs://bafkreiggz5srh65jpqrbslils375fptumccvsal2jra6x5cfpnssestqoa",
                    tagline: "Base is for everyone",
                    url: "https://flows.wtf/base"
                }),
                IChainalysisSanctionsList(sanctionsOracle),
                topStrategies
            )
        );

        baseFlow = address(new ERC1967Proxy(baseFlowImpl, initData));
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("BaseFlowImpl: ", addressToString(baseFlowImpl))));
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(baseFlow))));
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
