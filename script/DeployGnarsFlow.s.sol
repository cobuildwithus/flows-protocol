// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { FlowTypes } from "../src/storage/FlowStorage.sol";
import { IFlow, ICustomFlow } from "../src/interfaces/IFlow.sol";
import { IChainalysisSanctionsList } from "../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";
import { Flow } from "../src/Flow.sol";
import { SingleAllocatorStrategy } from "../src/allocation-strategies/SingleAllocatorStrategy.sol";
import { ERC721VotesStrategy } from "../src/allocation-strategies/ERC721VotesStrategy.sol";
import { IAllocationStrategy } from "../src/interfaces/IAllocationStrategy.sol";
import { IERC721Votes } from "../src/interfaces/IERC721Votes.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IFlowTCR } from "../src/tcr/interfaces/IGeneralizedTCR.sol";
import { ITCRFactory } from "../src/tcr/interfaces/ITCRFactory.sol";
import { IManagedFlow } from "../src/interfaces/IManagedFlow.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

/// @title DeployGnarsFlow
/// @notice Deploys a standalone CustomFlow (Gnars Flow) with an ERC721 voting strategy
/// and two child flows (Storytelling, Gnars Shredders) governed by the ERC721 voting strategy.
contract DeployGnarsFlow is DeployScript {
    // Deployed contract addresses
    address public GnarsFlow;
    address public GnarsFlowImpl;
    address public erc721VotingStrategy;
    // Child-specific governance
    address public flowTCRStory;
    address public flowTCRShredders;
    address public erc20ArbitratorStory;
    address public erc20ArbitratorShredders;

    string public contractName;

    function deploy() internal override {
        // ------------------------------------------------------------------
        // Env vars
        // ------------------------------------------------------------------
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address erc721TokenAddress = vm.envAddress("ERC721_TOKEN_ADDRESS");
        address superToken = vm.envAddress("SUPER_TOKEN");
        uint256 tokenVoteWeight = 1000 * 1e18;
        // Single allocator: deployer has full allocation power at parent level
        uint32 baselinePoolFlowRatePercent = 750000; // 75% out of 1e6
        uint32 managerRewardPoolFlowRatePercent = 250000; // 25% out of 1e6
        uint32 bonusPoolQuorumBps = 200_000; // 20% with PERCENTAGE_SCALE = 1e6
        address sanctionsOracle = 0x3A91A31cB3dC49b4db9Ce721F50a9D076c8D739B;
        contractName = "GnarsFlow";
        address connectPoolAdmin = 0x6eD3cec4ec39786094350FbCf10a6761B93f350d;

        // // TCR params (hardcoded sensible defaults)
        // // Coin costs $0.05 each -> $5 application fee = 100 tokens
        uint256 submissionBaseDeposit = 100e18; // 100 tokens (~$5)
        uint256 removalBaseDeposit = 100e18; // same as submission
        uint256 submissionChallengeBaseDeposit = 100e18; // challenger stake
        uint256 removalChallengeBaseDeposit = 100e18; // challenger stake
        uint256 challengePeriodDuration = 3 days; // time to challenge requests
        uint256 votingPeriod = 3 days; // commit phase duration
        uint256 votingDelay = 12 hours; // delay before voting starts
        uint256 revealPeriod = 1 days; // reveal phase duration
        uint256 arbitrationCost = 1e14; // minimal non-zero cost (0.0001 token)
        // TCR params (test-friendly: low costs and short timelines)
        // Deposits set to ~0.01 token, all windows ~2 minutes for quick iteration
        // uint256 submissionBaseDeposit = 1e16; // 0.01 token
        // uint256 removalBaseDeposit = 1e16; // 0.01 token
        // uint256 submissionChallengeBaseDeposit = 1e16; // 0.01 token
        // uint256 removalChallengeBaseDeposit = 1e16; // 0.01 token
        // uint256 challengePeriodDuration = 2 minutes; // quick challenge window for testing
        // uint256 votingPeriod = 2 minutes; // short commit/vote duration
        // uint256 votingDelay = 2 minutes; // short delay before voting starts
        // uint256 revealPeriod = 2 minutes; // short reveal phase
        // uint256 arbitrationCost = 1e16; // ~0.01 token arbitration cost

        // ------------------------------------------------------------------
        // Strategy (SingleAllocatorStrategy implementation + proxy)
        // ------------------------------------------------------------------
        address singleAllocImpl = _loadImplementation("SingleAllocatorStrategyImpl");
        bytes memory strategyInitData = abi.encodeCall(
            SingleAllocatorStrategy.initialize,
            (initialOwner, deployerAddress)
        );
        address singleAllocatorStrategy = address(new ERC1967Proxy(singleAllocImpl, strategyInitData));
        IAllocationStrategy[] memory topStrategies = new IAllocationStrategy[](1);
        topStrategies[0] = IAllocationStrategy(singleAllocatorStrategy);

        // Children governed by ERC721Votes
        address votingImpl = _loadImplementation("ERC721VotesStrategyImpl");
        bytes memory votingInitData = abi.encodeCall(
            ERC721VotesStrategy.initialize,
            (initialOwner, IERC721Votes(erc721TokenAddress), tokenVoteWeight)
        );
        erc721VotingStrategy = address(new ERC1967Proxy(votingImpl, votingInitData));

        // ------------------------------------------------------------------
        // Flow proxy using shared CustomFlow implementation, with manager set to deployer initially
        // ------------------------------------------------------------------
        GnarsFlowImpl = _loadImplementation("CustomFlowImpl");

        bytes memory flowInitData = abi.encodeCall(
            ICustomFlow.initialize,
            (
                initialOwner,
                superToken,
                GnarsFlowImpl,
                deployerAddress,
                address(0),
                address(0),
                connectPoolAdmin,
                IFlow.FlowParams({
                    baselinePoolFlowRatePercent: baselinePoolFlowRatePercent,
                    managerRewardPoolFlowRatePercent: managerRewardPoolFlowRatePercent,
                    bonusPoolQuorumBps: bonusPoolQuorumBps
                }),
                FlowTypes.RecipientMetadata({
                    title: "Gnars Flow",
                    description: string.concat(
                        unicode"Gnars funds shredders to build a community-owned alternative to corporate sponsorship."
                    ),
                    image: "https://www.gnars.com/images/gnars.webp",
                    tagline: "Gnars world wide",
                    url: "https://flows.wtf/gnars"
                }),
                IChainalysisSanctionsList(sanctionsOracle),
                topStrategies
            )
        );

        GnarsFlow = address(new ERC1967Proxy(GnarsFlowImpl, flowInitData));

        // ------------------------------------------------------------------
        // Deploy child flows: Storytelling & Gnars Shredders (manager = deployer initially)
        // ------------------------------------------------------------------
        FlowTypes.RecipientMetadata memory storytellingMeta = FlowTypes.RecipientMetadata({
            title: "Storytelling",
            description: string.concat(
                unicode"We fund content creators who capture and share Gnars stories that ",
                unicode"inspire action and grow the movement."
            ),
            image: string.concat(
                "https://dmo9tcngmx442k9p.public.blob.vercel-storage.com/",
                "Screenshot%202025-06-05%20at%2012.30.27%E2%80%AFPM-",
                "YuaolP330nlygjBEb5uSJkW0USpZp0.png"
            ),
            tagline: string.concat(
                "We Fund Content Creators Who Capture and Share Gnars Stories ",
                "That Inspire Action and Grow the Movement"
            ),
            url: "https://flows.wtf/gnars"
        });

        FlowTypes.RecipientMetadata memory shreddersMeta = FlowTypes.RecipientMetadata({
            title: "Gnars Shredders",
            description: string.concat(
                unicode"Gnars aims to rethink how shredders get paid by building a ",
                unicode"community-owned alternative to sponsorship middlemen."
            ),
            image: string.concat(
                "https://dmo9tcngmx442k9p.public.blob.vercel-storage.com/",
                "89E4E93D-B32F-426C-89E4-3E17213FF465-",
                "WLO04tAYAXcjM9h6T6RriUTFnbtmxl.jpg"
            ),
            tagline: string.concat(
                "Elevate and fund dedicated shredders who embody the Gnars ethos, ",
                "positively impact local skateparks, waves, streets, and trails, and ",
                "amplify Gnars visibility and its treasure."
            ),
            url: "https://flows.wtf/gnars"
        });

        IAllocationStrategy[] memory childStrategies = new IAllocationStrategy[](1);
        childStrategies[0] = IAllocationStrategy(erc721VotingStrategy);

        (, address storytelling) = Flow(GnarsFlow).addFlowRecipient(
            keccak256(abi.encode(storytellingMeta)),
            storytellingMeta,
            deployerAddress,
            address(0),
            childStrategies
        );

        (, address shredders) = Flow(GnarsFlow).addFlowRecipient(
            keccak256(abi.encode(shreddersMeta)),
            shreddersMeta,
            deployerAddress,
            address(0),
            childStrategies
        );

        Flow(GnarsFlow).setManager(initialOwner);

        // ------------------------------------------------------------------
        // Deploy TCR + Arbitrator for Storytelling child via factory
        // ------------------------------------------------------------------
        address tcrFactoryAddr = 0x61881cACA64903354E3A3Bfd0DFc31f046E2b540;
        ITCRFactory.DeployedContracts memory storyDeployed = ITCRFactory(tcrFactoryAddr).deployFlowTCR(
            ITCRFactory.FlowTCRParams({
                flowContract: IManagedFlow(storytelling),
                arbitratorExtraData: "",
                registrationMetaEvidence: "",
                clearingMetaEvidence: "",
                governor: initialOwner,
                submissionBaseDeposit: submissionBaseDeposit,
                removalBaseDeposit: removalBaseDeposit,
                submissionChallengeBaseDeposit: submissionChallengeBaseDeposit,
                removalChallengeBaseDeposit: removalChallengeBaseDeposit,
                challengePeriodDuration: challengePeriodDuration,
                requiredRecipientType: FlowTypes.RecipientType.ExternalAccount
            }),
            ITCRFactory.ArbitratorParams({
                votingPeriod: votingPeriod,
                votingDelay: votingDelay,
                revealPeriod: revealPeriod,
                arbitrationCost: arbitrationCost
            }),
            ITCRFactory.ERC20Params({ initialOwner: initialOwner, name: storytellingMeta.title, symbol: "TCR" }),
            ITCRFactory.RewardPoolParams({ superToken: ISuperToken(superToken) }),
            ITCRFactory.TokenEmitterParams({
                curveSteepness: 21000000000000,
                basePrice: 4000000000000,
                maxPriceIncrease: 2000000000000000000,
                supplyOffset: -335000000000000000000000000,
                priceDecayPercent: 300000000000000000,
                perTimeUnit: 50000000000000000000,
                founderRewardAddress: address(0),
                founderRewardDuration: 0
            })
        );
        flowTCRStory = storyDeployed.tcrAddress;
        erc20ArbitratorStory = storyDeployed.arbitratorAddress;
        // Wire manager reward pool to stream to token holders, then set manager to TCR
        Flow(storytelling).setManagerRewardPool(storyDeployed.rewardPoolAddress);
        Flow(storytelling).resetFlowRate();
        Flow(storytelling).setManager(flowTCRStory);

        // ------------------------------------------------------------------
        // Deploy TCR + Arbitrator for Shredders child via factory
        // ------------------------------------------------------------------
        ITCRFactory.DeployedContracts memory shreddersDeployed = ITCRFactory(tcrFactoryAddr).deployFlowTCR(
            ITCRFactory.FlowTCRParams({
                flowContract: IManagedFlow(shredders),
                arbitratorExtraData: "",
                registrationMetaEvidence: "",
                clearingMetaEvidence: "",
                governor: initialOwner,
                submissionBaseDeposit: submissionBaseDeposit,
                removalBaseDeposit: removalBaseDeposit,
                submissionChallengeBaseDeposit: submissionChallengeBaseDeposit,
                removalChallengeBaseDeposit: removalChallengeBaseDeposit,
                challengePeriodDuration: challengePeriodDuration,
                requiredRecipientType: FlowTypes.RecipientType.ExternalAccount
            }),
            ITCRFactory.ArbitratorParams({
                votingPeriod: votingPeriod,
                votingDelay: votingDelay,
                revealPeriod: revealPeriod,
                arbitrationCost: arbitrationCost
            }),
            ITCRFactory.ERC20Params({ initialOwner: initialOwner, name: shreddersMeta.title, symbol: "TCR" }),
            ITCRFactory.RewardPoolParams({ superToken: ISuperToken(superToken) }),
            ITCRFactory.TokenEmitterParams({
                curveSteepness: 21000000000000,
                basePrice: 4000000000000,
                maxPriceIncrease: 2000000000000000000,
                supplyOffset: -335000000000000000000000000,
                priceDecayPercent: 300000000000000000,
                perTimeUnit: 50000000000000000000,
                founderRewardAddress: address(0),
                founderRewardDuration: 0
            })
        );
        flowTCRShredders = shreddersDeployed.tcrAddress;
        erc20ArbitratorShredders = shreddersDeployed.arbitratorAddress;
        // Wire manager reward pool to stream to token holders, then set manager to TCR
        Flow(shredders).setManagerRewardPool(shreddersDeployed.rewardPoolAddress);
        Flow(shredders).resetFlowRate();
        Flow(shredders).setManager(flowTCRShredders);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("GnarsFlowImpl: ", addressToString(GnarsFlowImpl))));
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(GnarsFlow))));
        vm.writeLine(filePath, string(abi.encodePacked("StoryTCR: ", addressToString(flowTCRStory))));
        vm.writeLine(filePath, string(abi.encodePacked("StoryArbitrator: ", addressToString(erc20ArbitratorStory))));
        vm.writeLine(filePath, string(abi.encodePacked("ShreddersTCR: ", addressToString(flowTCRShredders))));
        vm.writeLine(
            filePath,
            string(abi.encodePacked("ShreddersArbitrator: ", addressToString(erc20ArbitratorShredders)))
        );
    }

    function getContractName() internal view override returns (string memory) {
        return contractName;
    }
}
