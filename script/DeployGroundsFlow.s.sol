// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { FlowTypes } from "../src/storage/FlowStorage.sol";
import { IFlow, ICustomFlow } from "../src/interfaces/IFlow.sol";
import { IChainalysisSanctionsList } from "../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";
import { CustomFlow } from "../src/flows/CustomFlow.sol";
import { Flow } from "../src/Flow.sol";
import { ERC721VotesStrategy } from "../src/allocation-strategies/ERC721VotesStrategy.sol";
import { IAllocationStrategy } from "../src/interfaces/IAllocationStrategy.sol";
import { IERC721Votes } from "../src/interfaces/IERC721Votes.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title DeployGroundsFlow
/// @notice Deploys a standalone CustomFlow (Grounds Flow) with an ERC721 voting strategy and a single child flow (Grounds Meetups) governed by SingleAllocatorStrategy.
contract DeployGroundsFlow is DeployScript {
    // Deployed contract addresses
    address public groundsFlow;
    address public groundsFlowImpl;
    address public erc721VotingStrategy;

    string public contractName;

    // Managers
    address internal constant ROCKETMAN = 0x289715fFBB2f4b482e2917D2f183FeAb564ec84F;

    function deploy() internal override {
        // ------------------------------------------------------------------
        // Env vars
        // ------------------------------------------------------------------
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address erc721TokenAddress = vm.envAddress("ERC721_TOKEN_ADDRESS");
        address superToken = vm.envAddress("SUPER_TOKEN");
        uint256 tokenVoteWeight = vm.envUint("TOKEN_VOTE_WEIGHT");
        uint32 baselinePoolFlowRatePercent = uint32(vm.envUint("BASELINE_POOL_FLOW_RATE_PERCENT"));
        uint32 managerRewardPoolFlowRatePercent = uint32(vm.envUint("REWARDS_POOL_FLOW_RATE_PERCENT"));
        uint32 bonusPoolQuorumBps = uint32(vm.envUint("BONUS_POOL_QUORUM_BPS"));
        address sanctionsOracle = vm.envAddress("SANCTIONS_ORACLE");
        contractName = vm.envString("CONTRACT_NAME");

        // ------------------------------------------------------------------
        // Strategy (implementation + proxy)
        // ------------------------------------------------------------------
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
        groundsFlowImpl = _loadImplementation("CustomFlowImpl");
        groundsFlow = address(new ERC1967Proxy(groundsFlowImpl, ""));

        // Initialize proxy
        ICustomFlow(groundsFlow).initialize({
            initialOwner: initialOwner,
            superToken: superToken,
            flowImpl: groundsFlowImpl,
            manager: ROCKETMAN,
            managerRewardPool: address(0),
            parent: address(0),
            flowParams: IFlow.FlowParams({
                baselinePoolFlowRatePercent: baselinePoolFlowRatePercent,
                managerRewardPoolFlowRatePercent: managerRewardPoolFlowRatePercent,
                bonusPoolQuorumBps: bonusPoolQuorumBps
            }),
            metadata: FlowTypes.RecipientMetadata({
                title: "Grounds Flow",
                description: "Grow the Grounds community around the world through collaborative projects and events.",
                image: "ipfs://bafkreigroundsflow1234567890abcdefghijklmnopqrstuvwxyz",
                tagline: "Grounds for everyone",
                url: "https://flows.wtf/grounds"
            }),
            sanctionsOracle: IChainalysisSanctionsList(sanctionsOracle),
            strategies: topStrategies
        });

        // ------------------------------------------------------------------
        // Deploy child flow: Grounds Meetups
        // ------------------------------------------------------------------
        FlowTypes.RecipientMetadata memory meetupsMeta = FlowTypes.RecipientMetadata({
            title: "Grounds Meetups",
            description: "Support local Grounds community meetups and workshops.",
            image: "ipfs://bafkreigroundsmeetupmeta1234567890abcdefghijk",
            tagline: "Meet IRL",
            url: "https://flows.wtf/grounds/meetups"
        });

        IAllocationStrategy[] memory childStrategies = new IAllocationStrategy[](1);
        childStrategies[0] = IAllocationStrategy(erc721VotingStrategy);

        (, address meetups) = Flow(groundsFlow).addFlowRecipient(
            keccak256(abi.encode(meetupsMeta)),
            meetupsMeta,
            ROCKETMAN,
            address(0),
            childStrategies
        );

        // Optionally set more params on child, e.g., manager already set via addFlowRecipient.
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("GroundsFlowImpl: ", addressToString(groundsFlowImpl))));
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(groundsFlow))));
    }

    function getContractName() internal view override returns (string memory) {
        return contractName;
    }
}
