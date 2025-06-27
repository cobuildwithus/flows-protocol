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

/// @title DeployGardensFlow
/// @notice Deploys a standalone CustomFlow (Gardens Flow) with 7 child flows for different allocation groups, all using SingleAllocatorStrategy with PAUL as allocator
contract DeployGardensFlow is DeployScript {
    // Deployed contract addresses
    address public gardensFlow;
    address public gardensFlowImpl;

    string public contractName;

    // Track deployed SingleAllocatorStrategy addresses for logging
    address[] public singleAllocatorStrategies;

    // Manager and allocator
    address internal constant PAUL = 0x809C9f8dd8CA93A41c3adca4972Fa234C28F7714;
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
        contractName = vm.envString("CONTRACT_NAME");

        // ------------------------------------------------------------------
        // Top-level strategy - SingleAllocatorStrategy with PAUL
        // ------------------------------------------------------------------
        IAllocationStrategy[] memory topStrategies = _singleAllocator(PAUL, initialOwner);

        // ------------------------------------------------------------------
        // Flow proxy using shared CustomFlow implementation
        // ------------------------------------------------------------------
        gardensFlowImpl = _loadImplementation("CustomFlowImpl");
        gardensFlow = address(new ERC1967Proxy(gardensFlowImpl, ""));

        // Initialize proxy with ROCKETMAN as initial manager
        ICustomFlow(gardensFlow).initialize({
            initialOwner: initialOwner,
            superToken: superToken,
            flowImpl: gardensFlowImpl,
            manager: ROCKETMAN,
            managerRewardPool: address(0),
            parent: address(0),
            flowParams: IFlow.FlowParams({
                baselinePoolFlowRatePercent: baselinePoolFlowRatePercent,
                managerRewardPoolFlowRatePercent: managerRewardPoolFlowRatePercent,
                bonusPoolQuorumBps: bonusPoolQuorumBps
            }),
            metadata: FlowTypes.RecipientMetadata({
                title: unicode"⚘GARDEN",
                description: unicode"Gardens is a community governance platform that helps people allocate shared resources as effectively as possible.\n\nOur platform lets communities govern themselves intelligently, using innovative mechanism design to give decision-making power to the people closest to the work, while protecting the greater collective from abuse and apathy.\n\nOrganizations that thrive on Gardens:\n\nExist for a mission, not just profit\nBenefit from decentralized security and resilience\n\nThese include open source projects, pop-up cities, web3 ecosystems, chapter-based orgs, activists, and many other public goods providers — digital or IRL.",
                image: "ipfs://QmYwTPdtxi8JVkpv8AzPSvvxH4pmR19QBVNdK8uZErnfZi",
                tagline: "Community governance platform",
                url: "https://flows.wtf/gardens"
            }),
            sanctionsOracle: IChainalysisSanctionsList(sanctionsOracle),
            strategies: topStrategies
        });

        // ------------------------------------------------------------------
        // Deploy child flows: 7 allocation groups
        // ------------------------------------------------------------------

        // 1. Core Contributors - 30%
        (, address coreContributors) = Flow(gardensFlow).addFlowRecipient(
            keccak256(abi.encode("CoreContributors")),
            FlowTypes.RecipientMetadata({
                title: "Core Contributors",
                description: "Allocated to the Core Contributors of the Gardens platform for their work building, maintaining, and growing both the open source software and the people and communities it serves.",
                image: "ipfs://bafkreicwysydsaeutdkdvmmk5ecy35twyolmgmzaabntbtdodbwootr6ru",
                tagline: "Building the Gardens platform",
                url: "https://flows.wtf/gardens"
            }),
            PAUL,
            address(0),
            topStrategies
        );

        // 2. Funding Sources - 30%
        (, address fundingSources) = Flow(gardensFlow).addFlowRecipient(
            keccak256(abi.encode("FundingSources")),
            FlowTypes.RecipientMetadata({
                title: "Funding Sources",
                description: "Allocated to the people and organizations who contributed funding to the development of Gardens v2.",
                image: "ipfs://bafkreif6loe2r5py6wcdpvvdw3cudiu3py7f3y65bhqe3na7luwkb5y23q",
                tagline: "Gardens v2 funders",
                url: "https://flows.wtf/gardens"
            }),
            PAUL,
            address(0),
            topStrategies
        );

        // 3. Growth Fund - 20%
        (, address growthFund) = Flow(gardensFlow).addFlowRecipient(
            keccak256(abi.encode("GrowthFund")),
            FlowTypes.RecipientMetadata({
                title: "Growth Fund",
                description: "Allocated to a funding pool in the Gardineros community to fund ongoing work on the Gardens platform.",
                image: "ipfs://bafkreiga4kyogpzbhdtbglhtxq5yj65ojgnw52y62nzmwvtffknoldlyhq",
                tagline: "Ongoing contributions and growth initiatives",
                url: "https://flows.wtf/gardens"
            }),
            PAUL,
            address(0),
            topStrategies
        );

        // 4. Gardens Communities + Members - 10%
        (, address gardensCommunities) = Flow(gardensFlow).addFlowRecipient(
            keccak256(abi.encode("GardensCommunities")),
            FlowTypes.RecipientMetadata({
                title: "Gardens Communities + Members",
                description: "Allocated to the communities and users of the Gardens platform.",
                image: "ipfs://bafkreidf57s7n75edygitbfvvfgz5ff6uxygdpy3gkx4z7ptgfubjxnkri",
                tagline: "Gardens users",
                url: "https://flows.wtf/gardens"
            }),
            PAUL,
            address(0),
            topStrategies
        );

        // 5. 1Hive - 5%
        (, address oneHive) = Flow(gardensFlow).addFlowRecipient(
            keccak256(abi.encode("1Hive")),
            FlowTypes.RecipientMetadata({
                title: "1Hive",
                description: "Allocated to our incubating DAO, 1Hive.",
                image: "ipfs://bafkreiewgtxym52n5zzhv7afsxrikcw5gjb3eihbppmpy2pr2qpf323uva",
                tagline: "Our incubating DAO",
                url: "https://flows.wtf/gardens"
            }),
            PAUL,
            address(0),
            topStrategies
        );

        // 6. Allo Ecosystem - 2.5%
        (, address alloEcosystem) = Flow(gardensFlow).addFlowRecipient(
            keccak256(abi.encode("AlloEcosystem")),
            FlowTypes.RecipientMetadata({
                title: "Allo Ecosystem",
                description: "Allocated to the ecosystem of builders in the Allo.Capital community.",
                image: "ipfs://bafkreiemcoyf7ujo35j3cbqgzuivq6uyf5supc7jqaeaewlseiguurs3we",
                tagline: "Allo builders",
                url: "https://flows.wtf/gardens"
            }),
            PAUL,
            address(0),
            topStrategies
        );

        // 7. Gardens v1 Team - 2.5%
        (, address gardensV1Team) = Flow(gardensFlow).addFlowRecipient(
            keccak256(abi.encode("GardensV1Team")),
            FlowTypes.RecipientMetadata({
                title: "Gardens v1 Team",
                description: "Allocated to the core contributors of Gardens v1.",
                image: "ipfs://bafkreidc2ckfg5d3otqgn6odozeu5yxj363byjo5t4lzx66srd55bmhcci",
                tagline: "Gardens v1 core contributors",
                url: "https://flows.wtf/gardens"
            }),
            PAUL,
            address(0),
            topStrategies
        );

        // Transfer management from ROCKETMAN to PAUL
        // Flow(gardensFlow).setManager(PAUL);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("GardensFlowImpl: ", addressToString(gardensFlowImpl))));
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(gardensFlow))));
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
