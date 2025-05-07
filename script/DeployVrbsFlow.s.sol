// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TokenVerifier } from "../src/state-proof/TokenVerifier.sol";
import { FlowTypes } from "../src/storage/FlowStorage.sol";
import { IFlow, IERC721Flow } from "../src/interfaces/IFlow.sol";
import { IChainalysisSanctionsList } from "../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";
import { VrbsFlow } from "../src/VrbsFlow.sol";

contract DeployVrbsFlow is DeployScript {
    address public vrbsFlow;
    address public vrbsFlowImplementation;

    function deploy() internal override {
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address superToken = vm.envAddress("SUPER_TOKEN");
        uint256 tokenVoteWeight = vm.envUint("TOKEN_VOTE_WEIGHT");
        uint32 baselinePoolFlowRatePercent = uint32(vm.envUint("BASELINE_POOL_FLOW_RATE_PERCENT"));
        uint32 managerRewardPoolFlowRatePercent = uint32(vm.envUint("REWARDS_POOL_FLOW_RATE_PERCENT"));

        // New parameters from vm.env
        address sanctionsOracle = vm.envAddress("SANCTIONS_ORACLE");
        uint32 bonusPoolQuorumBps = uint32(vm.envUint("BONUS_POOL_QUORUM_BPS"));

        // Deploy VrbsFlow implementation
        VrbsFlow vrbsFlowImpl = new VrbsFlow();
        vrbsFlowImplementation = address(vrbsFlowImpl);
        vrbsFlow = address(new ERC1967Proxy(address(vrbsFlowImpl), ""));

        // Prepare initialization data
        IERC721Flow(vrbsFlow).initialize({
            initialOwner: initialOwner,
            superToken: superToken,
            erc721Token: tokenAddress,
            flowImpl: address(vrbsFlowImpl),
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
            sanctionsOracle: IChainalysisSanctionsList(sanctionsOracle)
        });
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("VrbsFlowImpl: ", addressToString(vrbsFlowImplementation))));
        vm.writeLine(filePath, string(abi.encodePacked("VrbsFlow: ", addressToString(vrbsFlow))));
        // Get bonus and baseline pools from NounsFlow contract
        address bonusPool = address(IFlow(vrbsFlow).bonusPool());
        address baselinePool = address(IFlow(vrbsFlow).baselinePool());

        // Write bonus and baseline pool addresses to deployment details
        vm.writeLine(filePath, string(abi.encodePacked("BonusPool: ", addressToString(address(bonusPool)))));
        vm.writeLine(filePath, string(abi.encodePacked("BaselinePool: ", addressToString(address(baselinePool)))));
    }

    function getContractName() internal pure override returns (string memory) {
        return "VrbsFlow";
    }
}
