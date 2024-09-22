// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { DeployScript } from "./DeployScript.s.sol";
import { NounsFlow } from "../src/NounsFlow.sol";
import { ERC20VotesMintable } from "../src/ERC20VotesMintable.sol";
import { RewardPool } from "../src/RewardPool.sol";
import { TCRFactory } from "../src/tcr/TCRFactory.sol";
import { FlowTCR } from "../src/tcr/FlowTCR.sol";
import { IFlow } from "../src/interfaces/IFlow.sol";
import { FlowTypes } from "../src/storage/FlowStorageV1.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TokenVerifier } from "../src/state-proof/TokenVerifier.sol";
import { GeneralizedTCRStorageV1 } from "../src/tcr/storage/GeneralizedTCRStorageV1.sol";
import { IArbitrator } from "../src/tcr/interfaces/IArbitrator.sol";
import { ITCRFactory } from "../src/tcr/interfaces/ITCRFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IManagedFlow } from "../src/interfaces/IManagedFlow.sol";
import { IFlowTCR } from "../src/tcr/interfaces/IGeneralizedTCR.sol";
import { INounsFlow } from "../src/interfaces/IFlow.sol";
import { IRewardPool } from "../src/interfaces/IRewardPool.sol";
import { IERC20VotesMintable } from "../src/interfaces/IERC20VotesMintable.sol";
import { ERC20VotesArbitrator } from "../src/tcr/ERC20VotesArbitrator.sol";
import { IERC20VotesArbitrator } from "../src/tcr/interfaces/IERC20VotesArbitrator.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

contract DeployNounsFlow is DeployScript {
    address public nounsFlow;
    address public tokenVerifier;
    address public nounsFlowImplementation;

    address public erc20Arbitrator;
    address public erc20ArbitratorImplementation;

    address public erc20Mintable;
    address public erc20MintableImplementation;

    address public flowTCR;
    address public flowTCRImplementation;

    address public rewardPool;
    address public rewardPoolImplementation;

    address public tcrFactory;
    address public tcrFactoryImplementation;

    function deploy() internal override {
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address superToken = vm.envAddress("SUPER_TOKEN");
        address parent = vm.envAddress("PARENT");
        uint256 tokenVoteWeight = vm.envUint("TOKEN_VOTE_WEIGHT");
        uint32 baselinePoolFlowRatePercent = uint32(vm.envUint("BASELINE_POOL_FLOW_RATE_PERCENT"));
        uint32 managerRewardPoolFlowRatePercent = uint32(vm.envUint("REWARDS_POOL_FLOW_RATE_PERCENT"));

        // New parameters from vm.env
        uint256 submissionBaseDeposit = vm.envUint("SUBMISSION_BASE_DEPOSIT");
        uint256 removalBaseDeposit = vm.envUint("REMOVAL_BASE_DEPOSIT");
        uint256 submissionChallengeBaseDeposit = vm.envUint("SUBMISSION_CHALLENGE_BASE_DEPOSIT");
        uint256 removalChallengeBaseDeposit = vm.envUint("REMOVAL_CHALLENGE_BASE_DEPOSIT");
        uint256 challengePeriodDuration = vm.envUint("CHALLENGE_PERIOD_DURATION");
        uint256 votingPeriod = vm.envUint("VOTING_PERIOD");
        uint256 votingDelay = vm.envUint("VOTING_DELAY");
        uint256 revealPeriod = vm.envUint("REVEAL_PERIOD");
        uint256 appealPeriod = vm.envUint("APPEAL_PERIOD");
        uint256 appealCost = vm.envUint("APPEAL_COST");
        uint256 arbitrationCost = vm.envUint("ARBITRATION_COST");

        // Deploy NounsFlow implementation
        NounsFlow nounsFlowImpl = new NounsFlow();
        nounsFlowImplementation = address(nounsFlowImpl);
        nounsFlow = address(new ERC1967Proxy(address(nounsFlowImpl), ""));

        // Deploy TCRFactory implementation
        TCRFactory tcrFactoryImpl = new TCRFactory();
        tcrFactoryImplementation = address(tcrFactoryImpl);
        tcrFactory = address(new ERC1967Proxy(address(tcrFactoryImpl), ""));

        // Deploy ERC20VotesMintable implementation
        ERC20VotesMintable erc20MintableImpl = new ERC20VotesMintable();
        erc20MintableImplementation = address(erc20MintableImpl);
        erc20Mintable = address(new ERC1967Proxy(address(erc20MintableImpl), ""));

        // Deploy ERC20Arbitrator implementation
        ERC20VotesArbitrator erc20ArbitratorImpl = new ERC20VotesArbitrator();
        erc20ArbitratorImplementation = address(erc20ArbitratorImpl);
        erc20Arbitrator = address(new ERC1967Proxy(address(erc20ArbitratorImpl), ""));

        // Deploy RewardPool implementation
        RewardPool rewardPoolImpl = new RewardPool();
        rewardPoolImplementation = address(rewardPoolImpl);
        rewardPool = address(new ERC1967Proxy(address(rewardPoolImpl), ""));

        // Deploy FlowTCR implementation
        FlowTCR flowTCRImpl = new FlowTCR();
        flowTCRImplementation = address(flowTCRImpl);
        flowTCR = address(new ERC1967Proxy(address(flowTCRImpl), ""));

        // Deploy TokenVerifier
        TokenVerifier verifier = new TokenVerifier(tokenAddress);
        tokenVerifier = address(verifier);

        // Prepare initialization data
        INounsFlow(nounsFlow).initialize({
            initialOwner: initialOwner,
            verifier: tokenVerifier,
            superToken: superToken,
            flowImpl: address(nounsFlowImpl),
            manager: flowTCR,
            managerRewardPool: rewardPool,
            parent: parent,
            flowParams: IFlow.FlowParams({
                tokenVoteWeight: tokenVoteWeight,
                baselinePoolFlowRatePercent: baselinePoolFlowRatePercent,
                managerRewardPoolFlowRatePercent: managerRewardPoolFlowRatePercent
            }),
            metadata: FlowTypes.RecipientMetadata({
                title: "Nouns Flow",
                description: "An MVP of the Nouns Flow. Built by rocketman21.eth and wojci.eth",
                image: "ipfs://QmfZMtW2vDcdfH3TZdNAbMNm4Z1y16QHjuFwf8ff2NANAt",
                tagline: "Be nounish. Get rewarded.",
                url: "https://flows.wtf"
            })
        });

        // Initialize FlowTCR
        IFlowTCR(flowTCR).initialize({
            contractParams: GeneralizedTCRStorageV1.ContractParams({
                initialOwner: initialOwner,
                governor: initialOwner,
                flowContract: IManagedFlow(nounsFlow),
                arbitrator: IArbitrator(erc20Arbitrator),
                tcrFactory: ITCRFactory(tcrFactory),
                erc20: IERC20(erc20Mintable)
            }),
            tcrParams: GeneralizedTCRStorageV1.TCRParams({
                submissionBaseDeposit: submissionBaseDeposit,
                removalBaseDeposit: removalBaseDeposit,
                submissionChallengeBaseDeposit: submissionChallengeBaseDeposit,
                removalChallengeBaseDeposit: removalChallengeBaseDeposit,
                challengePeriodDuration: challengePeriodDuration,
                stakeMultipliers: [uint256(10000), uint256(10000), uint256(10000)],
                arbitratorExtraData: "",
                registrationMetaEvidence: "",
                clearingMetaEvidence: ""
            })
        });

        // Initialize RewardPool
        IRewardPool(rewardPool).initialize({
            superToken: ISuperToken(superToken),
            manager: erc20Mintable,
            funder: nounsFlow
        });

        // Initialize ERC20VotesMintable
        IERC20VotesMintable(erc20Mintable).initialize({
            initialOwner: initialOwner,
            minter: initialOwner,
            rewardPool: rewardPool,
            name: "Nouns Flow",
            symbol: "FLOWS"
        });

        // Initialize ERC20VotesArbitrator
        IERC20VotesArbitrator(erc20Arbitrator).initialize({
            initialOwner: initialOwner,
            votingToken: address(erc20Mintable),
            arbitrable: address(flowTCR),
            votingPeriod: votingPeriod,
            votingDelay: votingDelay,
            revealPeriod: revealPeriod,
            appealPeriod: appealPeriod,
            appealCost: appealCost,
            arbitrationCost: arbitrationCost
        });

        // Initialize TCRFactory
        ITCRFactory(tcrFactory).initialize({
            initialOwner: initialOwner,
            flowTCRImplementation: flowTCRImplementation,
            arbitratorImplementation: erc20ArbitratorImplementation,
            erc20Implementation: erc20MintableImplementation,
            rewardPoolImplementation: rewardPoolImplementation
        });
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(
            filePath,
            string(abi.encodePacked("ERC20VotesArbitratorImpl: ", addressToString(erc20ArbitratorImplementation)))
        );
        vm.writeLine(filePath, string(abi.encodePacked("TCRFactoryImpl: ", addressToString(tcrFactoryImplementation))));
        vm.writeLine(
            filePath,
            string(abi.encodePacked("ERC20VotesMintableImpl: ", addressToString(erc20MintableImplementation)))
        );
        vm.writeLine(filePath, string(abi.encodePacked("NounsFlowImpl: ", addressToString(nounsFlowImplementation))));
        vm.writeLine(filePath, string(abi.encodePacked("RewardPoolImpl: ", addressToString(rewardPoolImplementation))));
        vm.writeLine(filePath, string(abi.encodePacked("FlowTCRImpl: ", addressToString(flowTCRImplementation))));
        vm.writeLine(filePath, string(abi.encodePacked("TokenVerifier: ", addressToString(tokenVerifier))));
        vm.writeLine(filePath, string(abi.encodePacked("NounsFlow: ", addressToString(nounsFlow))));
        vm.writeLine(filePath, string(abi.encodePacked("RewardPool: ", addressToString(rewardPool))));
        vm.writeLine(filePath, string(abi.encodePacked("FlowTCR: ", addressToString(flowTCR))));
        vm.writeLine(filePath, string(abi.encodePacked("ERC20VotesArbitrator: ", addressToString(erc20Arbitrator))));
        vm.writeLine(filePath, string(abi.encodePacked("ERC20VotesMintable: ", addressToString(erc20Mintable))));
        vm.writeLine(filePath, string(abi.encodePacked("TCRFactory: ", addressToString(tcrFactory))));
    }

    function getContractName() internal pure override returns (string memory) {
        return "NounsFlow";
    }
}
