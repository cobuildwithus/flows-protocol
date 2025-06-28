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

/// @title DeploySingleAllocatorFlow
/// @notice Deploys a standalone CustomFlow with a single allocator
contract DeploySingleAllocatorFlow is DeployScript {
    // Deployed contract addresses
    address public singleAllocatorFlow;
    address public singleAllocatorFlowImpl;

    string public contractName;

    // Track deployed SingleAllocatorStrategy addresses for logging
    address[] public singleAllocatorStrategies;

    // Manager
    address internal constant ROCKETMAN = 0x289715fFBB2f4b482e2917D2f183FeAb564ec84F;

    function deploy() internal override {
        // ------------------------------------------------------------------
        // Env vars
        // ------------------------------------------------------------------
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address superToken = vm.envAddress("SUPER_TOKEN");
        uint32 baselinePoolFlowRatePercent = uint32(vm.envUint("BASELINE_POOL_FLOW_RATE_PERCENT"));
        uint32 managerRewardPoolFlowRatePercent = uint32(vm.envUint("REWARDS_POOL_FLOW_RATE_PERCENT"));
        uint32 bonusPoolQuorumBps = uint32(vm.envUint("BONUS_POOL_QUORUM_BPS"));
        address sanctionsOracle = vm.envAddress("SANCTIONS_ORACLE");
        address allocator = vm.envAddress("ALLOCATOR");
        address managerRewardPool = vm.envAddress("MANAGER_REWARD_POOL");
        contractName = vm.envString("CONTRACT_NAME");

        // ------------------------------------------------------------------
        // Top-level strategy - SingleAllocatorStrategy with allocator
        // ------------------------------------------------------------------
        IAllocationStrategy[] memory topStrategies = _singleAllocator(allocator, initialOwner);

        // ------------------------------------------------------------------
        // Flow proxy using shared CustomFlow implementation
        // ------------------------------------------------------------------
        singleAllocatorFlowImpl = _loadImplementation("CustomFlowImpl");
        singleAllocatorFlow = address(new ERC1967Proxy(singleAllocatorFlowImpl, ""));

        // Initialize proxy with ROCKETMAN as initial manager
        ICustomFlow(singleAllocatorFlow).initialize({
            initialOwner: initialOwner,
            superToken: superToken,
            flowImpl: singleAllocatorFlowImpl,
            manager: allocator,
            managerRewardPool: address(0),
            parent: address(0),
            flowParams: IFlow.FlowParams({
                baselinePoolFlowRatePercent: baselinePoolFlowRatePercent,
                managerRewardPoolFlowRatePercent: managerRewardPoolFlowRatePercent,
                bonusPoolQuorumBps: bonusPoolQuorumBps
            }),
            metadata: FlowTypes.RecipientMetadata({
                title: unicode"Vrbs Coffee's Public Good",
                description: unicode"Vrbs Coffee exists to fuel people on a mission. Whether that's chasing a creative idea, training for a race, or giving back to the world. We craft great coffee that powers purpose, and we use our profits to support causes that matter.",
                image: "https://imagedelivery.net/BXluQx4ige9GuW0Ia56BHw/716dbbeb-c537-4b65-a843-6f96f39a7200/original",
                tagline: "Fueling global impact",
                url: "https://flows.wtf"
            }),
            sanctionsOracle: IChainalysisSanctionsList(sanctionsOracle),
            strategies: topStrategies
        });
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(
            filePath,
            string(abi.encodePacked("SingleAllocatorFlowImpl: ", addressToString(singleAllocatorFlowImpl)))
        );
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(singleAllocatorFlow))));
    }

    function getContractName() internal view override returns (string memory) {
        return contractName;
    }

    /// @dev Deploys a SingleAllocatorStrategy with the given allocator and returns it as a single-item array.
    function _singleAllocator(address allocator, address owner) internal returns (IAllocationStrategy[] memory arr) {
        address impl = _loadImplementation("SingleAllocatorStrategyImpl");
        address proxy = address(new ERC1967Proxy(impl, ""));
        SingleAllocatorStrategy(proxy).initialize(owner, allocator);
        singleAllocatorStrategies.push(proxy);
        arr = new IAllocationStrategy[](1);
        arr[0] = IAllocationStrategy(proxy);
    }
}
