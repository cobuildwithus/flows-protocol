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

/// @title DeployRevnetFlow
/// @notice Deploys a standalone CustomFlow (Revnet Flow) with a single top-level flow using SingleAllocatorStrategy with ROCKETMAN as allocator
contract DeployRevnetFlow is DeployScript {
    // Deployed contract addresses
    address public revnetFlow;
    address public revnetFlowImpl;

    string public contractName;

    // Track deployed SingleAllocatorStrategy addresses for logging
    address[] public singleAllocatorStrategies;

    // Allocator
    address internal constant JANGO = 0x5138a42C3D5065debE950deBDa10C1f38150a908;
    address internal constant ROCKETMAN = 0x289715fFBB2f4b482e2917D2f183FeAb564ec84F;

    address internal constant COBUILD_SAFE = 0xc4079dc1F8F84711eee0942c192829f473Fc3C28;

    function deploy() internal override {
        // ------------------------------------------------------------------
        // Env vars
        // ------------------------------------------------------------------
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address superToken = vm.envAddress("SUPER_TOKEN");
        uint32 baselinePoolFlowRatePercent = 0;
        uint32 managerRewardPoolFlowRatePercent = 20000;
        uint32 bonusPoolQuorumBps = 1e6;
        address sanctionsOracle = vm.envAddress("SANCTIONS_ORACLE");
        contractName = "Revnet";

        address connectPoolAdmin = 0x6eD3cec4ec39786094350FbCf10a6761B93f350d;

        // ------------------------------------------------------------------
        // Top-level strategy - SingleAllocatorStrategy with JANGO
        // ------------------------------------------------------------------
        IAllocationStrategy[] memory topStrategies = _singleAllocator(JANGO, initialOwner);

        // ------------------------------------------------------------------
        // Flow proxy using shared CustomFlow implementation
        // ------------------------------------------------------------------
        revnetFlowImpl = _loadImplementation("CustomFlowImpl");

        bytes memory initData = abi.encodeCall(
            ICustomFlow.initialize,
            (
                initialOwner,
                superToken,
                revnetFlowImpl,
                ROCKETMAN,
                COBUILD_SAFE,
                address(0),
                connectPoolAdmin,
                IFlow.FlowParams({
                    baselinePoolFlowRatePercent: baselinePoolFlowRatePercent,
                    managerRewardPoolFlowRatePercent: managerRewardPoolFlowRatePercent,
                    bonusPoolQuorumBps: bonusPoolQuorumBps
                }),
                FlowTypes.RecipientMetadata({
                    title: unicode"Revnets",
                    description: unicode"Tokenize revenues and fundraises. 100% autonomous.",
                    image: "ipfs://bafkreib2mryveotw5bz3fllsvqs4cz2bneh6flghwpzzzxswbaiwwrph3e",
                    tagline: "Tokenize your revenues and fundraises",
                    url: "https://flows.wtf/revnets"
                }),
                IChainalysisSanctionsList(sanctionsOracle),
                topStrategies
            )
        );

        revnetFlow = address(new ERC1967Proxy(revnetFlowImpl, initData));

        // ------------------------------------------------------------------
        // Deploy child flows: allocation groups managed by JANGO
        // ------------------------------------------------------------------

        // 1. Core Revnet App / Team
        (, address coreRevnetTeam) = Flow(revnetFlow).addFlowRecipient(
            keccak256(abi.encode("CoreRevnetAppTeam")),
            FlowTypes.RecipientMetadata({
                title: "Core Team",
                description: "Allocated to the core team building and maintaining the Revnet protocol and app.",
                image: "ipfs://bafybeibyguqj5t2cl6kmpnhwxpcktn4xsrpdvk4mff2uc4o7dgorsljc5e",
                tagline: "Core Revnet team",
                url: "https://flows.wtf/revnets"
            }),
            JANGO,
            COBUILD_SAFE,
            topStrategies
        );

        // 2. Integrations
        (, address integrations) = Flow(revnetFlow).addFlowRecipient(
            keccak256(abi.encode("Integrations")),
            FlowTypes.RecipientMetadata({
                title: "Integrations",
                description: "Allocated to teams and contributors integrating Revnets with other platforms and services.",
                image: "ipfs://bafybeid4mt4fwq6phehaxy2vhuiocwrbiy3souhao2qggq6ozofx6jyxse",
                tagline: "Expanding Revnet integrations",
                url: "https://flows.wtf/revnets"
            }),
            JANGO,
            COBUILD_SAFE,
            topStrategies
        );

        // 3. Marketing / Explainers
        (, address marketing) = Flow(revnetFlow).addFlowRecipient(
            keccak256(abi.encode("MarketingExplainers")),
            FlowTypes.RecipientMetadata({
                title: "Marketing",
                description: "Allocated to marketing initiatives and content explaining Revnet.",
                image: "ipfs://bafybeie37hbz3fxf75rzvx6daedmbsfczuvsuz4eajq62cu7kqhjlzfzva",
                tagline: "Growing Revnet awareness",
                url: "https://flows.wtf/revnets"
            }),
            JANGO,
            COBUILD_SAFE,
            topStrategies
        );

        // 4. Sales / Closing Deals
        (, address sales) = Flow(revnetFlow).addFlowRecipient(
            keccak256(abi.encode("SalesClosingDeals")),
            FlowTypes.RecipientMetadata({
                title: "Sales",
                description: "Allocated to efforts that drive sales and close deals for Revnet.",
                image: "ipfs://bafybeiebt4dugvloc7gu7yiowjlz5tmvxi4z72z6k7dajqig2dgqsfxd5u",
                tagline: "Driving Revnet adoption",
                url: "https://flows.wtf/revnets"
            }),
            JANGO,
            COBUILD_SAFE,
            topStrategies
        );

        // 5. Live Revnets
        (, address liveRevnets) = Flow(revnetFlow).addFlowRecipient(
            keccak256(abi.encode("LiveRevnets")),
            FlowTypes.RecipientMetadata({
                title: "Live Revnets",
                description: "Allocated to the live Revnet instances and their ongoing maintenance.",
                image: "ipfs://bafybeiam4f3jzgej44wf5wybmoak7x3c3bkpockch7lbhtgmijzir7iamy",
                tagline: "Supporting live Revnet instances",
                url: "https://flows.wtf/revnets"
            }),
            JANGO,
            COBUILD_SAFE,
            topStrategies
        );

        // Transfer management from ROCKETMAN to JANGO
        Flow(revnetFlow).setManager(JANGO);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("RevnetFlowImpl: ", addressToString(revnetFlowImpl))));
        vm.writeLine(filePath, string(abi.encodePacked(contractName, ": ", addressToString(revnetFlow))));
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
