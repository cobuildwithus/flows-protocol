// Start of Selection
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { FlowTCR } from "../../src/tcr/FlowTCR.sol";
import { ERC20VotesMintable } from "../../src/ERC20VotesMintable.sol";
import { ERC20VotesArbitrator } from "../../src/tcr/ERC20VotesArbitrator.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGeneralizedTCR } from "../../src/tcr/interfaces/IGeneralizedTCR.sol";
import { IArbitrator } from "../../src/tcr/interfaces/IArbitrator.sol";
import { IArbitrable } from "../../src/tcr/interfaces/IArbitrable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ArbitratorStorageV1 } from "../../src/tcr/storage/ArbitratorStorageV1.sol";
import { FlowTypes } from "../../src/storage/FlowStorageV1.sol";
import { IManagedFlow } from "../../src/interfaces/IManagedFlow.sol";
import { IFlowTCR } from "../../src/tcr/interfaces/IGeneralizedTCR.sol";
import { ERC721FlowTest } from "../erc721-flow/ERC721Flow.t.sol";
import { TCRFactory } from "../../src/tcr/TCRFactory.sol";
import { TokenEmitter } from "../../src/TokenEmitter.sol";
import { ITCRFactory } from "../../src/tcr/interfaces/ITCRFactory.sol";
import { RewardPool } from "../../src/RewardPool.sol";
import { ProtocolRewards } from "../../src/protocol-rewards/ProtocolRewards.sol";
import { GeneralizedTCRStorageV1 } from "../../src/tcr/storage/GeneralizedTCRStorageV1.sol";

contract FlowTCRTest is ERC721FlowTest {
    // Contracts
    FlowTCR public flowTCR;
    ERC20VotesMintable public erc20Token;
    ERC20VotesArbitrator public arbitrator;
    RewardPool public rewardPool;
    TokenEmitter public tokenEmitter;
    ProtocolRewards public protocolRewards;

    // Addresses
    address public owner;
    address public governor;
    address public requester;
    address public challenger;
    address public swingVoter;
    address public recipient;
    address public WETH;
    address public protocolFeeRecipient;

    // Test Parameters
    uint256 public constant SUBMISSION_BASE_DEPOSIT = 100 ether;
    uint256 public constant REMOVAL_BASE_DEPOSIT = 100 ether;
    uint256 public constant SUBMISSION_CHALLENGE_BASE_DEPOSIT = 100 ether;
    uint256 public constant REMOVAL_CHALLENGE_BASE_DEPOSIT = 100 ether;
    uint256 public constant CHALLENGE_PERIOD = 3 days;
    uint256 public constant STAKE_MULTIPLIER_SHARED = 10000; // 100%
    uint256 public constant STAKE_MULTIPLIER_WINNER = 10000; // 100%
    uint256 public constant STAKE_MULTIPLIER_LOSER = 10000; // 100%

    // FlowTCR Parameters
    bytes public constant ARBITRATOR_EXTRA_DATA = "";
    string public constant REGISTRATION_META_EVIDENCE = "meta_evidence/registration";
    string public constant CLEARING_META_EVIDENCE = "meta_evidence/clearing";
    string public constant BASIC_EVIDENCE = "basic_evidence";
    bytes public EXTERNAL_ACCOUNT_ITEM_DATA;
    bytes public FLOW_RECIPIENT_ITEM_DATA;

    uint256[3] public STAKE_MULTIPLIERS = [
        uint256(STAKE_MULTIPLIER_SHARED),
        uint256(STAKE_MULTIPLIER_WINNER),
        uint256(STAKE_MULTIPLIER_LOSER)
    ];

    // Arbitrator Parameters
    uint256 public constant VOTING_PERIOD = 86_400; // MIN_VOTING_PERIOD
    uint256 public constant VOTING_DELAY = 1; // MIN_VOTING_DELAY
    uint256 public constant REVEAL_PERIOD = 86_400; // MIN_REVEAL_PERIOD
    uint256 public constant APPEAL_PERIOD = 21_600; // MIN_APPEAL_PERIOD
    uint256 public constant APPEAL_COST = 1e18 / 10_000; // MIN_APPEAL_COST
    uint256 public constant ARBITRATION_COST = 1e18 / 10_000; // MIN_ARBITRATION_COST

    function setUp() public virtual override {
        super.setUp();
        governor = address(this);
        requester = makeAddr("requester");
        challenger = makeAddr("challenger");
        owner = makeAddr("owner");
        swingVoter = makeAddr("swingVoter");
        recipient = makeAddr("recipient");
        WETH = makeAddr("weth");
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");

        protocolRewards = new ProtocolRewards();

        address rewardPoolImpl = address(new RewardPool());
        address tokenEmitterImpl = address(new TokenEmitter(address(protocolRewards), protocolFeeRecipient));
        address flowTCRImpl = address(new FlowTCR());
        address flowTCRProxy = address(new ERC1967Proxy(flowTCRImpl, ""));
        address arbitratorImpl = address(new ERC20VotesArbitrator());
        address arbitratorProxy = address(new ERC1967Proxy(arbitratorImpl, ""));
        address erc20TokenImpl = address(new ERC20VotesMintable());
        address erc20TokenProxy = address(new ERC1967Proxy(erc20TokenImpl, ""));
        address tokenEmitterProxy = address(new ERC1967Proxy(tokenEmitterImpl, ""));

        address tcrFactoryImpl = address(new TCRFactory());
        address tcrFactoryProxy = address(new ERC1967Proxy(tcrFactoryImpl, ""));

        rewardPool = deployRewardPool(address(superToken), erc20TokenProxy, flowTCRProxy);

        ITCRFactory(tcrFactoryProxy).initialize({
            initialOwner: owner,
            flowTCRImplementation: flowTCRImpl,
            arbitratorImplementation: arbitratorImpl,
            erc20Implementation: erc20TokenImpl,
            rewardPoolImplementation: rewardPoolImpl,
            tokenEmitterImplementation: tokenEmitterImpl,
            weth: WETH
        });

        EXTERNAL_ACCOUNT_ITEM_DATA = abi.encode(recipient, recipientMetadata, FlowTypes.RecipientType.ExternalAccount);
        FLOW_RECIPIENT_ITEM_DATA = abi.encode(address(0), recipientMetadata, FlowTypes.RecipientType.FlowContract);

        flowTCR = FlowTCR(flowTCRProxy);
        flowTCR.initialize(
            GeneralizedTCRStorageV1.ContractParams({
                initialOwner: address(owner),
                governor: governor,
                flowContract: IManagedFlow(address(flow)),
                arbitrator: IArbitrator(arbitratorProxy),
                tcrFactory: ITCRFactory(tcrFactoryProxy),
                erc20: IERC20(erc20TokenProxy)
            }),
            GeneralizedTCRStorageV1.TCRParams({
                submissionBaseDeposit: SUBMISSION_BASE_DEPOSIT,
                removalBaseDeposit: REMOVAL_BASE_DEPOSIT,
                submissionChallengeBaseDeposit: SUBMISSION_CHALLENGE_BASE_DEPOSIT,
                removalChallengeBaseDeposit: REMOVAL_CHALLENGE_BASE_DEPOSIT,
                challengePeriodDuration: CHALLENGE_PERIOD,
                stakeMultipliers: STAKE_MULTIPLIERS,
                arbitratorExtraData: ARBITRATOR_EXTRA_DATA,
                registrationMetaEvidence: REGISTRATION_META_EVIDENCE,
                clearingMetaEvidence: CLEARING_META_EVIDENCE,
                requiredRecipientType: FlowTypes.RecipientType.None
            }),
            IFlowTCR.TokenEmitterParams({
                curveSteepness: int256(1e18) / 100,
                basePrice: int256(1e18) / 3000,
                maxPriceIncrease: int256(1e18) / 300,
                supplyOffset: int256(1e18) * 1000
            })
        );

        erc20Token = ERC20VotesMintable(erc20TokenProxy);
        erc20Token.initialize(governor, governor, address(rewardPool), "Test Token", "TST");

        arbitrator = ERC20VotesArbitrator(arbitratorProxy);
        arbitrator.initialize(
            address(owner),
            address(erc20Token),
            address(flowTCR),
            VOTING_PERIOD,
            VOTING_DELAY,
            REVEAL_PERIOD,
            APPEAL_PERIOD,
            APPEAL_COST,
            ARBITRATION_COST
        );

        // Mint tokens to test addresses
        erc20Token.mint(requester, 1000 ether);
        erc20Token.mint(challenger, 1000 ether);
        erc20Token.mint(swingVoter, 1000 ether);

        vm.prank(flow.owner());
        flow.setManager(address(flowTCR));

        // Approve FlowTCR to spend tokens
        vm.prank(requester);
        erc20Token.approve(address(flowTCR), type(uint256).max);
        vm.prank(challenger);
        erc20Token.approve(address(flowTCR), type(uint256).max);
    }

    // Helper Functions
    function submitItem(bytes memory _itemData, address _submitter) internal returns (bytes32 itemID) {
        vm.prank(_submitter);
        itemID = flowTCR.addItem(_itemData);
    }

    /**
     * @notice Helper function to commit, reveal votes, and execute ruling for a given dispute ID
     * @param disputeID The ID of the dispute to process
     * @param winner The winner of the dispute
     */
    function voteAndExecute(uint256 disputeID, IArbitrable.Party winner) internal {
        // Advance time to reveal period
        advanceTime(VOTING_DELAY + 2);

        // Commit votes
        bytes32 requesterSecretHash = keccak256(abi.encode(uint256(1), "For registration", bytes32("salt")));
        vm.prank(requester);
        arbitrator.commitVote(disputeID, requesterSecretHash);

        bytes32 challengerSecretHash = keccak256(abi.encode(uint256(2), "Against registration", bytes32("salt2")));
        vm.prank(challenger);
        arbitrator.commitVote(disputeID, challengerSecretHash);

        bytes32 swingVoterSecretHash = keccak256(abi.encode(uint256(winner), "Swing vote", bytes32("salt3")));
        vm.prank(swingVoter);
        arbitrator.commitVote(disputeID, swingVoterSecretHash);

        // Advance time to reveal period
        advanceTime(VOTING_PERIOD);

        // Reveal votes
        vm.prank(requester);
        arbitrator.revealVote(disputeID, 1, "For registration", bytes32("salt"));

        vm.prank(challenger);
        arbitrator.revealVote(disputeID, 2, "Against registration", bytes32("salt2"));

        vm.prank(swingVoter);
        arbitrator.revealVote(disputeID, uint256(winner), "Swing vote", bytes32("salt3"));

        // Advance time to end of reveal and appeal periods
        advanceTime(REVEAL_PERIOD + APPEAL_PERIOD);

        // Execute the ruling
        arbitrator.executeRuling(disputeID);
    }

    // Helper function to challenge an item
    function challengeItem(bytes32 _itemID, address _challenger) internal returns (uint256) {
        vm.prank(_challenger);
        flowTCR.challengeRequest(_itemID, BASIC_EVIDENCE);

        // Get the dispute ID from the last request
        (, uint256 disputeID, , , , , , , , ) = flowTCR.getRequestInfo(_itemID, 0);
        return disputeID;
    }

    function advanceTime(uint256 _seconds) internal {
        uint blockTime = 2; // 2 seconds per block
        vm.warp(block.timestamp + _seconds);
        vm.roll(block.number + _seconds / blockTime);
    }
}
