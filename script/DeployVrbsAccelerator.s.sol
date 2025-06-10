// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { FlowTypes } from "../src/storage/FlowStorage.sol";
import { IFlow, ICustomFlow } from "../src/interfaces/IFlow.sol";
import { IChainalysisSanctionsList } from "../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";
import { CustomFlow } from "../src/flows/CustomFlow.sol";
import { Flow } from "../src/Flow.sol";
import { ERC721VotingStrategy } from "../src/allocation-strategies/ERC721VotingStrategy.sol";
import { SingleAllocatorStrategy } from "../src/allocation-strategies/SingleAllocatorStrategy.sol";
import { IAllocationStrategy } from "../src/interfaces/IAllocationStrategy.sol";
import { IERC721Checkpointable } from "../src/interfaces/IERC721Checkpointable.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title DeployVrbsAccelerator
/// @notice Deploys the Vrbs Accelerator Top-level Flow (CustomFlow) with an ERC721 voting strategy
///         and sets up child flows which use a SingleAllocatorStrategy.
contract DeployVrbsAccelerator is DeployScript {
    // Top-level flow addresses
    address public vrbsAccelerator;
    address public vrbsAcceleratorImpl;

    // Strategy addresses
    address public erc721VotingStrategy;

    // Friendly name for deployment artefact
    string public contractName;

    // Example curator/manager addresses (keep from reference script)
    address internal constant RIDERWAY = 0x2830e21792019CE670fBc548AacB004b08c7f71f;
    address internal constant ROCKETMAN = 0x289715fFBB2f4b482e2917D2f183FeAb564ec84F;

    // Helper declared at contract scope below is used for strategies

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

        // ---------------------------------------------------------------------
        // Deploy voting strategy for the top-level flow
        // ---------------------------------------------------------------------
        ERC721VotingStrategy votingStrategy = new ERC721VotingStrategy();
        votingStrategy.initialize(initialOwner, IERC721Checkpointable(erc721TokenAddress), tokenVoteWeight);
        erc721VotingStrategy = address(votingStrategy);

        IAllocationStrategy[] memory topStrategies = new IAllocationStrategy[](1);
        topStrategies[0] = IAllocationStrategy(erc721VotingStrategy);

        // ---------------------------------------------------------------------
        // Deploy CustomFlow implementation and proxy
        // ---------------------------------------------------------------------
        CustomFlow impl = new CustomFlow();
        vrbsAcceleratorImpl = address(impl);
        vrbsAccelerator = address(new ERC1967Proxy(vrbsAcceleratorImpl, ""));

        // ---------------------------------------------------------------------
        // Initialize the proxy
        // ---------------------------------------------------------------------
        ICustomFlow(vrbsAccelerator).initialize({
            initialOwner: initialOwner,
            superToken: superToken,
            flowImpl: vrbsAcceleratorImpl,
            manager: initialOwner,
            managerRewardPool: address(0),
            parent: address(0),
            flowParams: IFlow.FlowParams({
                baselinePoolFlowRatePercent: baselinePoolFlowRatePercent,
                managerRewardPoolFlowRatePercent: managerRewardPoolFlowRatePercent,
                bonusPoolQuorumBps: bonusPoolQuorumBps
            }),
            metadata: FlowTypes.RecipientMetadata({
                title: "Vrbs Accelerator",
                description: unicode"Back and mentor Vrbs-branded ventures that onboard the public to crypto, uplift their communities, and reach break-even within six months—returning a share of revenue to fuel future grants.",
                image: "ipfs://bafkreices36hj7akzelx2jfw6dxmkfxfjis44koxcolkbisqopufcbolju",
                tagline: "Founders welcome",
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
        FlowTypes.RecipientMetadata memory realMadridMeta = FlowTypes.RecipientMetadata({
            title: "Real Madrid",
            description: "Support Real Madrid's community initiatives and youth development programs through Vrbs ecosystem integration.",
            image: "ipfs://bafkreifrolsnnjbklsvs5uutiua336m2y33kb2zggj4e3kion5672uuz3u",
            tagline: "Football legends",
            url: "https://flows.wtf/vrbs/realmadrid"
        });

        FlowTypes.RecipientMetadata memory healthAiMeta = FlowTypes.RecipientMetadata({
            title: "Vrbs Health AI",
            description: "Develop AI-powered health solutions leveraging blockchain for secure data management and community wellness initiatives.",
            image: "ipfs://bafkreices36hj7akzelx2jfw6dxmkfxfjis44koxcolkbisqopufcbolju",
            tagline: "AI for wellness",
            url: "https://flows.wtf/vrbs/healthai"
        });

        // Add child flows to top-level accelerator
        (, address realMadrid) = Flow(vrbsAccelerator).addFlowRecipient(
            keccak256(abi.encode(realMadridMeta)),
            realMadridMeta,
            ROCKETMAN,
            address(0),
            _singleAllocator(RIDERWAY, initialOwner)
        );

        (, address healthAi) = Flow(vrbsAccelerator).addFlowRecipient(
            keccak256(abi.encode(healthAiMeta)),
            healthAiMeta,
            ROCKETMAN,
            address(0),
            _singleAllocator(ROCKETMAN, initialOwner)
        );

        // ------------------------------------------------------------------
        // Deploy budgets under each child flow
        // ------------------------------------------------------------------
        FlowTypes.RecipientMetadata memory realMadridBudgetMeta = FlowTypes.RecipientMetadata({
            title: "Real Madrid Budget",
            description: "Budget allocation for Real Madrid community projects.",
            image: "ipfs://bafkreiabcdefghijklmnopqrstuvwxyz123456789abcdefghi",
            tagline: "Supporting football legends",
            url: "https://flows.wtf/vrbs/realmadrid/budget"
        });

        FlowTypes.RecipientMetadata memory healthAiBudgetMeta = FlowTypes.RecipientMetadata({
            title: "Health AI Budget",
            description: "Budget to fuel AI-powered health product development.",
            image: "ipfs://bafkreizyxwvutsrqponmlkjihgfedcba987654321zyxwvutsrqponmlk",
            tagline: "Empowering AI-assisted wellness",
            url: "https://flows.wtf/vrbs/healthai/budget"
        });

        // Add budgets (second-level)
        Flow(realMadrid).addFlowRecipient(
            keccak256(abi.encode(realMadridBudgetMeta)),
            realMadridBudgetMeta,
            RIDERWAY,
            address(0),
            _singleAllocator(RIDERWAY, initialOwner)
        );

        Flow(healthAi).addFlowRecipient(
            keccak256(abi.encode(healthAiBudgetMeta)),
            healthAiBudgetMeta,
            ROCKETMAN,
            address(0),
            _singleAllocator(ROCKETMAN, initialOwner)
        );

        // Set manager for real madrid to riderway
        Flow(realMadrid).setManager(RIDERWAY);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("VrbsAcceleratorImpl: ", addressToString(vrbsAcceleratorImpl))));
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(vrbsAccelerator))));

        // Record pool addresses for convenience
        address bonusPool = address(IFlow(vrbsAccelerator).bonusPool());
        address baselinePool = address(IFlow(vrbsAccelerator).baselinePool());
        vm.writeLine(filePath, string(abi.encodePacked("BonusPool: ", addressToString(bonusPool))));
        vm.writeLine(filePath, string(abi.encodePacked("BaselinePool: ", addressToString(baselinePool))));
    }

    function getContractName() internal view override returns (string memory) {
        return contractName;
    }

    /// @dev Deploys a SingleAllocatorStrategy with the given allocator and returns it as a single-item array.
    function _singleAllocator(address allocator, address owner) internal returns (IAllocationStrategy[] memory arr) {
        SingleAllocatorStrategy sas = new SingleAllocatorStrategy();
        sas.initialize(owner, allocator);
        arr = new IAllocationStrategy[](1);
        arr[0] = IAllocationStrategy(address(sas));
    }
}
