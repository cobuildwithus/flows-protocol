// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { FlowTypes } from "../src/storage/FlowStorage.sol";
import { IFlow, IRevolutionFlow } from "../src/interfaces/IFlow.sol";
import { IChainalysisSanctionsList } from "../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";
import { RevolutionFlow } from "../src/flows/RevolutionFlow.sol";
import { SelfManagedFlow } from "../src/flows/SelfManagedFlow.sol";
import { Flow } from "../src/Flow.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployRevolutionFlow is DeployScript {
    address public revolutionFlow;
    address public revolutionFlowImplementation;
    string public contractName;

    address riderway = 0x2830e21792019CE670fBc548AacB004b08c7f71f;
    address rocketman = 0x289715fFBB2f4b482e2917D2f183FeAb564ec84F;

    function deploy() internal override {
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address erc721TokenAddress = vm.envAddress("ERC721_TOKEN_ADDRESS");
        address erc20TokenAddress = vm.envAddress("ERC20_TOKEN_ADDRESS");
        address superToken = vm.envAddress("SUPER_TOKEN");
        uint256 tokenVoteWeight = vm.envUint("TOKEN_VOTE_WEIGHT");
        uint256 erc20TokenVoteWeight = vm.envUint("ERC20_TOKEN_VOTE_WEIGHT");
        uint32 baselinePoolFlowRatePercent = uint32(vm.envUint("BASELINE_POOL_FLOW_RATE_PERCENT"));
        uint32 managerRewardPoolFlowRatePercent = uint32(vm.envUint("REWARDS_POOL_FLOW_RATE_PERCENT"));
        contractName = vm.envString("CONTRACT_NAME");

        // New parameters from vm.env
        address sanctionsOracle = vm.envAddress("SANCTIONS_ORACLE");
        uint32 bonusPoolQuorumBps = uint32(vm.envUint("BONUS_POOL_QUORUM_BPS"));

        // Deploy RevolutionFlow implementation
        RevolutionFlow revolutionFlowImpl = new RevolutionFlow();
        revolutionFlowImplementation = address(revolutionFlowImpl);
        revolutionFlow = address(new ERC1967Proxy(address(revolutionFlowImpl), ""));

        // Prepare initialization data
        IRevolutionFlow(revolutionFlow).initialize({
            initialOwner: initialOwner,
            superToken: superToken,
            flowImpl: address(revolutionFlowImpl),
            manager: initialOwner,
            managerRewardPool: address(0),
            parent: address(0),
            flowParams: IFlow.FlowParams({
                tokenVoteWeight: tokenVoteWeight,
                baselinePoolFlowRatePercent: baselinePoolFlowRatePercent,
                managerRewardPoolFlowRatePercent: managerRewardPoolFlowRatePercent,
                bonusPoolQuorumBps: bonusPoolQuorumBps
            }),
            metadata: FlowTypes.RecipientMetadata({
                title: "Vrbs Flow",
                description: unicode"Create Vrbs-branded products, services, experiences, and art that reach and empower the public, improve public spaces, and generate positive externalities—always in an open, daring, and sustainable way.",
                image: "ipfs://QmfZMtW2vDcdfH3TZdNAbMNm4Z1y16QHjuFwf8ff2NANAt",
                tagline: "Build something that matters with Vrbs.",
                url: "https://flows.wtf/vrbs"
            }),
            sanctionsOracle: IChainalysisSanctionsList(sanctionsOracle),
            data: abi.encode(address(revolutionFlowImpl), erc721TokenAddress, erc20TokenAddress, erc20TokenVoteWeight)
        });

        // Create first-level recipients (similar to AddRevolutionTestRecipients.s.sol)
        FlowTypes.RecipientMetadata memory artistsBudgetMeta = FlowTypes.RecipientMetadata({
            title: "Artists Budget",
            description: "Create Vrbs art and media that amplify funded ventures, spark public curiosity about Vrbs, and beautify shared public spaces.",
            image: "ipfs://bafkreifrolsnnjbklsvs5uutiua336m2y33kb2zggj4e3kion5672uuz3u",
            tagline: "Artists welcome",
            url: "https://flows.wtf/vrbs"
        });

        FlowTypes.RecipientMetadata memory acceleratorMeta = FlowTypes.RecipientMetadata({
            title: "Vrbs Accelerator",
            description: unicode"Back and mentor Vrbs-branded ventures that onboard the public to crypto, uplift their communities, and reach break-even within six months—returning a share of revenue to fuel future grants.",
            image: "ipfs://bafkreices36hj7akzelx2jfw6dxmkfxfjis44koxcolkbisqopufcbolju",
            tagline: "Founders welcome",
            url: "https://flows.wtf/vrbs"
        });

        // Add first-level recipients to the main flow
        (, address artistsBudget) = Flow(revolutionFlow).addFlowRecipient(
            keccak256(abi.encode(artistsBudgetMeta)),
            artistsBudgetMeta,
            initialOwner,
            address(0),
            bytes("")
        );

        (, address accelerator) = Flow(revolutionFlow).addFlowRecipient(
            keccak256(abi.encode(acceleratorMeta)),
            acceleratorMeta,
            initialOwner,
            address(0),
            bytes("")
        );

        address selfManagedFlowImpl = address(new SelfManagedFlow());

        // Create second-level recipients for Accelerator
        FlowTypes.RecipientMetadata memory realMadridMeta = FlowTypes.RecipientMetadata({
            title: "Real Madrid",
            description: "Support Real Madrid's community initiatives and youth development programs through Vrbs ecosystem integration.",
            image: "ipfs://bafkreifrolsnnjbklsvs5uutiua336m2y33kb2zggj4e3kion5672uuz3u",
            tagline: "Football legends",
            url: "https://flows.wtf/vrbs/realmadrid"
        });

        FlowTypes.RecipientMetadata memory healthAiMeta = FlowTypes.RecipientMetadata({
            title: "Vrbs Health AI",
            description: "Develop AI-powered health solutions that leverage blockchain for secure data management and community wellness initiatives.",
            image: "ipfs://bafkreices36hj7akzelx2jfw6dxmkfxfjis44koxcolkbisqopufcbolju",
            tagline: "AI for wellness",
            url: "https://flows.wtf/vrbs/healthai"
        });

        // Add second-level recipients to the Accelerator
        (, address realMadrid) = Flow(accelerator).addFlowRecipient(
            keccak256(abi.encode(realMadridMeta)),
            realMadridMeta,
            riderway,
            address(0),
            abi.encode(address(selfManagedFlowImpl), riderway)
        );

        (, address healthAi) = Flow(accelerator).addFlowRecipient(
            keccak256(abi.encode(healthAiMeta)),
            healthAiMeta,
            rocketman,
            address(0),
            abi.encode(address(selfManagedFlowImpl), rocketman)
        );

        // Create second-level recipients for Artists Budget
        FlowTypes.RecipientMetadata memory realArtistsBudgetMeta = FlowTypes.RecipientMetadata({
            title: "Real Artists Budget",
            description: "Fund traditional artists and art initiatives that promote cultural heritage and artistic expression within the Vrbs ecosystem.",
            image: "ipfs://bafkreiabcdefghijklmnopqrstuvwxyz123456789abcdefghijklmnopq",
            tagline: "Supporting traditional artists",
            url: "https://flows.wtf/vrbs/realartists"
        });

        FlowTypes.RecipientMetadata memory aiArtistsBudgetMeta = FlowTypes.RecipientMetadata({
            title: "AI Artists Budget",
            description: "Support artists leveraging AI technologies to create innovative digital art and explore the intersection of technology and creativity.",
            image: "ipfs://bafkreizyxwvutsrqponmlkjihgfedcba987654321zyxwvutsrqponmlk",
            tagline: "Empowering AI-assisted creativity",
            url: "https://flows.wtf/vrbs/aiartists"
        });

        // Add second-level recipients to the Artists Budget
        (, address realArtistsBudget) = Flow(artistsBudget).addFlowRecipient(
            keccak256(abi.encode(realArtistsBudgetMeta)),
            realArtistsBudgetMeta,
            riderway,
            address(0),
            abi.encode(address(selfManagedFlowImpl), riderway)
        );

        (, address aiArtistsBudget) = Flow(artistsBudget).addFlowRecipient(
            keccak256(abi.encode(aiArtistsBudgetMeta)),
            aiArtistsBudgetMeta,
            rocketman,
            address(0),
            abi.encode(address(selfManagedFlowImpl), rocketman)
        );
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(
            filePath,
            string(abi.encodePacked("RevolutionFlowImpl: ", addressToString(revolutionFlowImplementation)))
        );
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(revolutionFlow))));
        // Get bonus and baseline pools from NounsFlow contract
        address bonusPool = address(IFlow(revolutionFlow).bonusPool());
        address baselinePool = address(IFlow(revolutionFlow).baselinePool());

        // Write bonus and baseline pool addresses to deployment details
        vm.writeLine(filePath, string(abi.encodePacked("BonusPool: ", addressToString(address(bonusPool)))));
        vm.writeLine(filePath, string(abi.encodePacked("BaselinePool: ", addressToString(address(baselinePool)))));
    }

    function getContractName() internal view override returns (string memory) {
        return contractName;
    }
}
