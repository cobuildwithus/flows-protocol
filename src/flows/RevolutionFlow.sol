// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { Flow } from "../Flow.sol";
import { IRevolutionFlow } from "../interfaces/IFlow.sol";
import { IERC721Checkpointable } from "../interfaces/IERC721Checkpointable.sol";
import { FlowVotes } from "../library/FlowVotes.sol";
import { FlowRates } from "../library/FlowRates.sol";
import { ERC721FlowLibrary } from "../library/ERC721FlowLibrary.sol";
import { IChainalysisSanctionsList } from "../interfaces/external/chainalysis/IChainalysisSanctionsList.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RevolutionFlow is IRevolutionFlow, Flow {
    using FlowVotes for Storage;
    using FlowRates for Storage;
    using ERC721FlowLibrary for Storage;

    // The ERC721 voting token contract used to get the voting power of an account
    IERC721Checkpointable public erc721Votes;

    // The ERC20 voting token contract used to get the voting power of an account
    IERC20 public erc20Votes;

    // The weight of each single erc20 token
    uint256 public erc20TokenVoteWeight;

    // Whether voting is enabled or not
    bool public votingEnabled;

    constructor() payable initializer {}

    function initialize(
        address _initialOwner,
        address _erc721Token,
        address _erc20Token,
        uint256 _erc20TokenVoteWeight,
        address _superToken,
        address _flowImpl,
        address _manager,
        address _managerRewardPool,
        address _parent,
        FlowParams calldata _flowParams,
        RecipientMetadata calldata _metadata,
        IChainalysisSanctionsList _sanctionsOracle
    ) public initializer {
        if (_erc721Token == address(0)) revert ADDRESS_ZERO();
        if (_erc20Token == address(0)) revert ADDRESS_ZERO();

        erc721Votes = IERC721Checkpointable(_erc721Token);
        erc20Votes = IERC20(_erc20Token);
        erc20TokenVoteWeight = _erc20TokenVoteWeight;

        __Flow_init(
            _initialOwner,
            _superToken,
            _flowImpl,
            _manager,
            _managerRewardPool,
            _parent,
            _flowParams,
            _metadata,
            _sanctionsOracle
        );

        emit ERC721VotingTokenChanged(_erc721Token);
        emit ERC20VotingTokenChanged(_erc20Token);
        emit ERC20VotingWeightChanged(0, _erc20TokenVoteWeight);
    }

    /**
     * @notice Cast a vote for a set of grant addresses.
     * @param tokenIds The tokenIds that the voter is using to vote.
     * @param recipientIds The recpientIds of the grant recipients.
     * @param percentAllocations The basis points of the vote to be split with the recipients.
     */
    function castVotes(
        uint256[] calldata tokenIds,
        bytes32[] calldata recipientIds,
        uint32[] calldata percentAllocations
    ) external nonReentrant onlyVotingEnabled {
        fs.validateAllocations(recipientIds, percentAllocations, PERCENTAGE_SCALE);

        uint256 totalFlowsToUpdate = 0;
        bool shouldUpdateFlowRate = false;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (!canVoteWithToken(tokenIds[i], msg.sender)) revert NOT_ABLE_TO_VOTE_WITH_TOKEN();
            (uint256 flowsToUpdate, bool updateFlowRate) = _setVotesAllocationForTokenId(
                tokenIds[i],
                recipientIds,
                percentAllocations,
                msg.sender
            );
            totalFlowsToUpdate += flowsToUpdate;
            shouldUpdateFlowRate = shouldUpdateFlowRate || updateFlowRate;
        }

        _afterVotesCast(recipientIds, totalFlowsToUpdate, shouldUpdateFlowRate);
    }

    /**
     * @notice Checks if a given address can vote with a specific token
     * @param tokenId The ID of the token to check voting rights for
     * @param voter The address of the potential voter
     * @return bool True if the voter can vote with the token, false otherwise
     */
    function canVoteWithToken(uint256 tokenId, address voter) public view returns (bool) {
        address tokenOwner = erc721Votes.ownerOf(tokenId);
        // check if the token owner has delegated their voting power to the voter
        // erc721checkpointable falls back to the owner
        // if the owner hasn't delegated so this will work for the owner as well
        address delegate = erc721Votes.delegates(tokenOwner);
        return voter == delegate;
    }

    /**
     * @notice Function to calculate the total vote weight of all tokens used for voting
     * @dev This function can be overridden in derived contracts to implement custom logic
     * @return uint256 The total vote weight of all tokens used for voting
     */
    function totalTokenSupplyVoteWeight() public view override returns (uint256) {
        return erc721Votes.totalSupply() * fs.tokenVoteWeight;
    }

    /**
     * @notice Enable voting for the flow
     */
    function enableVoting() external onlyManager {
        votingEnabled = true;
    }

    /**
     * @notice Disable voting for the flow
     */
    function disableVoting() external onlyManager {
        votingEnabled = false;
    }

    /**
     * @notice Modifier to ensure voting is enabled
     */
    modifier onlyVotingEnabled() {
        if (!votingEnabled) revert VOTING_DISABLED();
        _;
    }

    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function is virtual to allow for different deployment strategies in derived contracts
     * @param metadata The recipient's metadata like title, description, etc.
     * @param flowManager The address of the flow manager for the new contract
     * @param managerRewardPool The address of the manager reward pool for the new contract
     * @return recipient address The address of the newly created Flow contract
     */
    function _deployFlowRecipient(
        RecipientMetadata calldata metadata,
        address flowManager,
        address managerRewardPool
    ) internal override returns (address recipient) {
        recipient = fs.deployFlowRecipient(
            metadata,
            flowManager,
            managerRewardPool,
            owner(),
            address(this),
            address(erc721Votes),
            PERCENTAGE_SCALE
        );
    }
}
