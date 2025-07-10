// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { FlowTypes } from "../src/storage/FlowStorage.sol";
import { IFlow, ICustomFlow } from "../src/interfaces/IFlow.sol";
import { IChainalysisSanctionsList } from "../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";
import { Flow } from "../src/Flow.sol";
import { ERC721VotesStrategy } from "../src/allocation-strategies/ERC721VotesStrategy.sol";
import { SingleAllocatorStrategy } from "../src/allocation-strategies/SingleAllocatorStrategy.sol";
import { IAllocationStrategy } from "../src/interfaces/IAllocationStrategy.sol";
import { IERC721Votes } from "../src/interfaces/IERC721Votes.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/// @title DeployVrbsAccelerator
/// @notice Deploys the Vrbs Accelerator Top-level Flow (CustomFlow) with an ERC721 voting strategy
///         and sets up child flows which use a SingleAllocatorStrategy.
contract DeployVrbsAccelerator is DeployScript {
    // Top-level flow addresses
    address public vrbsFlow;
    address public vrbsFlowImpl;
    address public vrbsAccelerator;

    // Strategy addresses
    address public erc721VotingStrategy;

    // Track deployed SingleAllocatorStrategy addresses for logging
    address[] public singleAllocatorStrategies;

    // Friendly name for deployment artefact
    string public contractName;

    // Example curator/manager addresses (keep from reference script)
    address internal constant ROCKETMAN = 0x289715fFBB2f4b482e2917D2f183FeAb564ec84F;

    function deploy() internal override {
        // ---------------------------------------------------------------------
        // Load required environment variables
        // ---------------------------------------------------------------------
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address erc721TokenAddress = vm.envAddress("ERC721_TOKEN_ADDRESS");
        address superToken = vm.envAddress("SUPER_TOKEN");
        uint256 tokenVoteWeight = vm.envUint("TOKEN_VOTE_WEIGHT");
        uint32 baselinePoolFlowRatePercent = uint32(vm.envUint("BASELINE_POOL_FLOW_RATE_PERCENT"));
        uint32 managerRewardPoolFlowRatePercent = uint32(vm.envUint("REWARDS_POOL_FLOW_RATE_PERCENT"));
        uint32 bonusPoolQuorumBps = uint32(vm.envUint("BONUS_POOL_QUORUM_BPS"));
        address sanctionsOracle = vm.envAddress("SANCTIONS_ORACLE");
        contractName = vm.envString("CONTRACT_NAME");

        address connectPoolAdmin = 0x6eD3cec4ec39786094350FbCf10a6761B93f350d;

        // ---------------------------------------------------------------------
        // Deploy voting strategy (implementation + proxy)
        // ---------------------------------------------------------------------
        address votingImpl = _loadImplementation("ERC721VotesStrategyImpl");
        erc721VotingStrategy = address(new ERC1967Proxy(votingImpl, ""));
        ERC721VotesStrategy(erc721VotingStrategy).initialize(
            initialOwner,
            IERC721Votes(erc721TokenAddress),
            tokenVoteWeight
        );

        IAllocationStrategy[] memory topStrategies = new IAllocationStrategy[](1);
        topStrategies[0] = IAllocationStrategy(erc721VotingStrategy);

        // ------------------------------------------------------------------
        // Flow proxy using shared CustomFlow implementation
        // ------------------------------------------------------------------
        vrbsFlowImpl = _loadImplementation("CustomFlowImpl");
        vrbsFlow = address(new ERC1967Proxy(vrbsFlowImpl, ""));

        // Initialize proxy
        ICustomFlow(vrbsFlow).initialize({
            initialOwner: initialOwner,
            superToken: superToken,
            flowImpl: vrbsFlowImpl,
            manager: ROCKETMAN,
            managerRewardPool: address(0),
            parent: address(0),
            connectPoolAdmin: connectPoolAdmin,
            flowParams: IFlow.FlowParams({
                baselinePoolFlowRatePercent: baselinePoolFlowRatePercent,
                managerRewardPoolFlowRatePercent: managerRewardPoolFlowRatePercent,
                bonusPoolQuorumBps: bonusPoolQuorumBps
            }),
            metadata: FlowTypes.RecipientMetadata({
                title: "Vrbs Flow",
                description: unicode"## Our mission \n\n Do good with no expectation of return. Steward public spaces. Create positive externalities. Empower people to uplift their communities. Embrace absurdity & difference. Teach people about Vrbs & crypto. Dare greatly. Have fun. ## Our goals \n\n Create Vrbs-branded products, services, experiences, and art that reach and empower the public, improve public spaces, and generate positive externalities—always in an open, daring, and sustainable way.",
                image: "ipfs://bafybeibj6cb2nyzxgpoi5l2cnhqv4ituu63wxp6tls45sqadvd7ysyn55i",
                tagline: "We fund the next generation of visionaries making a difference in their local communities.",
                url: "https://flows.wtf/vrbs"
            }),
            sanctionsOracle: IChainalysisSanctionsList(sanctionsOracle),
            strategies: topStrategies
        });

        // ------------------------------------------------------------------
        // Deploy child flows (Real Madrid & Health AI) each with
        // a dedicated SingleAllocatorStrategy
        // ------------------------------------------------------------------

        // Metadata definitions
        FlowTypes.RecipientMetadata memory vrbsAcceleratorMeta = FlowTypes.RecipientMetadata({
            title: "Vrbs Accelerator",
            description: unicode"Back and mentor Vrbs-branded ventures that onboard the public to crypto, uplift their communities, and reach break-even within six months to help fuel future grants.",
            image: "ipfs://bafybeibj6cb2nyzxgpoi5l2cnhqv4ituu63wxp6tls45sqadvd7ysyn55i",
            tagline: "We fund the next generation of visionaries making a difference in their local communities.",
            url: "https://flows.wtf/vrbs"
        });

        FlowTypes.RecipientMetadata memory artistsBudgetsMeta = FlowTypes.RecipientMetadata({
            title: "Vrbs Artist Budgets",
            description: unicode"Fund artists working on Vrbs-branded creative projects that bring art to public spaces, onboard communities to crypto through creative expression, and celebrate the absurd beauty of decentralized culture.",
            image: "ipfs://bafybeibj6cb2nyzxgpoi5l2cnhqv4ituu63wxp6tls45sqadvd7ysyn55i",
            tagline: "Art for all",
            url: "https://flows.wtf/vrbs"
        });

        // Add child flows to top-level accelerator
        Flow(vrbsFlow).addFlowRecipient(
            keccak256(abi.encode(vrbsAcceleratorMeta)),
            vrbsAcceleratorMeta,
            ROCKETMAN,
            address(0),
            topStrategies
        );

        Flow(vrbsFlow).addFlowRecipient(
            keccak256(abi.encode(artistsBudgetsMeta)),
            artistsBudgetsMeta,
            ROCKETMAN,
            address(0),
            topStrategies
        );
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("VrbsFlowImpl: ", addressToString(vrbsFlowImpl))));
        vm.writeLine(filePath, string(abi.encodePacked("VrbsFlow: ", addressToString(vrbsFlow))));
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
