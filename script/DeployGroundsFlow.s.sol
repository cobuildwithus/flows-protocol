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
        address connectPoolAdmin = 0x6eD3cec4ec39786094350FbCf10a6761B93f350d;

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
            connectPoolAdmin: connectPoolAdmin,
            flowParams: IFlow.FlowParams({
                baselinePoolFlowRatePercent: baselinePoolFlowRatePercent,
                managerRewardPoolFlowRatePercent: managerRewardPoolFlowRatePercent,
                bonusPoolQuorumBps: bonusPoolQuorumBps
            }),
            metadata: FlowTypes.RecipientMetadata({
                title: "Grounds Flow",
                description: unicode"Our mission? Wake up! Be bold, pour freely, and brew good. Percolate stimulating ideas, with a rich blend of people and cultures. Stay the grind and distribute well. It might be a long shot, but by applying the right pressure, we have a robust opportunity to make a global impact.",
                image: "ipfs://bafkreich7a6w5m5a5u5dbh7kh5wqxfm6itbjqcdnv5fw5lgjo3uyq2evbe",
                tagline: "Grounds world wide",
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
            description: unicode"We fund grassroots gatherings designed to foster meaningful connections, share knowledge, and strengthen real-world relationships within the Grounds ecosystem—one cup at a time.\n\n#### Overview & Goals\nGrounds Coffee Connect provides funding to organize small, informal monthly coffee meetups that unite Grounds holders and crypto-curious individuals. The goal is to offer an easy, enjoyable way to connect, discuss ideas, and build lasting relationships within local communities.\n\n#### Funding Structure\n* Organizers receive at least **$50 USDC per month**, sufficient for refreshments for 3-5 attendees.\n* Extra rewards for exceptional community impact and creativity\n* Payments stream automatically every second while requirements are met\n\n#### Application Process\nSubmit an application with the following details:\n1. **Organizer Information:**\n* Name & Farcaster handle.\n* Brief background or previous community organizing experience.\n2. **Meetup Plan:**\n* City/region and proposed public venues (e.g., cafes, community spaces).\n* Intended schedule (frequency and typical day/time).\n* Strategy for promoting meetups publicly and attracting diverse attendees.\n3. **Community Vision:**\n* How your meetups will embody Grounds values\n* Initial ideas for discussions, activities, or ways to help newcomers feel comfortable.\n* Overall mission for your program as it relates to your city / local community\n4. **Acknowledgment:**\n* Confirm understanding and agreement with ongoing requirements.\n\n#### Ongoing Requirements\nTo maintain funding:\n* **Regular Meetups:** Host at least one meetup monthly.\n* **Minimum Attendance:** Ensure at least three attendees (including organizer).\n* **Public Accessibility:** Open events to all interested participants, with clear, advanced public announcements. Make sure to announce events beforehand on Farcaster.\n* **Venue Respect:** Use public venues responsibly; leave spaces tidy and maintain positive relationships.\n\n#### Documentation & Proof (Posted in /groundsdao on Farcaster)\nWithin 48 hours after each meetup:\n* **Visual Proof:** Clear photos or short videos (faces optional if privacy requested).\n* **Brief Summary:** Include date, venue, attendee count, and a short narrative about discussions or activities.\n* **Optional but Encouraged:** Highlight interesting insights, new member participation, or creative interactions.\n\n#### Grounds Community Standards\n* Foster a welcoming and inclusive atmosphere for everyone, especially newcomers.\n* Encourage genuine interactions and meaningful conversations.\n* Represent Grounds positively and accurately.\n* Maintain respectful and safe environments—no tolerance for harassment, discrimination, or illegal activities.\n\n#### Verification and Compliance\nOngoing eligibility confirmed via:\n* Timely, consistent Farcaster updates.\n* Informal community feedback.\n* Demonstrable adherence to meetup frequency, attendance, and openness requirements.\n\n#### Reasons for Funding Removal\nFunding may be paused or revoked if:\n* Monthly meetup quotas are missed without valid explanation.\n* Inadequate or misleading documentation provided.\n* Exclusive or invite-only events hosted.\n* Verified complaints regarding safety, harassment, or misconduct.\n* Non-compliance with venue rules or local laws.\n\n#### Tips for Successful Meetups\n* Keep events simple and consistent.\n* Vary venues to maintain freshness and community interest.\n* Actively promote meetups in advance on Farcaster and local community channels.\n* Be proactive in welcoming new attendees and facilitating conversation.\n* Consider guest speakers, themed discussions, cross-community events, or interactive activities.\n\n#### Curator Guidelines\n* Manage monthly budgets carefully, prioritizing high-quality applications aligned with Grounds values.\n* Ensure meetups remain genuinely engaging, open, and compliant.\n* Prioritize meetups that demonstrate authentic interactions, welcoming atmospheres, and growing community engagement.\n* Communicate transparently with applicants and organizers.\n* Use the trial period to gather feedback and insights for continuous improvement.\n\n#### Final Note\nThe Grounds Coffee Connect flow exists to nurture real human connections within our community. We support enthusiastic organizers committed to creating consistent, inclusive, and engaging meetups, reinforcing the bonds that make the Grounds community resilient and vibrant. Let's brew bold ideas together!",
            image: "ipfs://bafybeifcxrzv4cjzjbqmfjvbhezmno2dov74mqvp4doa5b7bkqacdgf5u4",
            tagline: "Percolate freely - IRL",
            url: "https://flows.wtf/grounds"
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
