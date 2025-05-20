// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { Flow } from "../Flow.sol";
import { IERC721Flow } from "../interfaces/IFlow.sol";
import { IERC721Checkpointable } from "../interfaces/IERC721Checkpointable.sol";
import { IRewardPool } from "../interfaces/IRewardPool.sol";
import { FlowVotes } from "../library/FlowVotes.sol";
import { FlowRates } from "../library/FlowRates.sol";
import { ERC721FlowLibrary } from "../library/ERC721FlowLibrary.sol";
import { IChainalysisSanctionsList } from "../interfaces/external/chainalysis/IChainalysisSanctionsList.sol";

contract ERC721Flow is IERC721Flow, Flow {
    using FlowVotes for Storage;
    using FlowRates for Storage;
    using ERC721FlowLibrary for Storage;

    // The ERC721 voting token contract used to get the voting power of an account
    IERC721Checkpointable public erc721Votes;

    constructor() payable initializer {}

    function initialize(
        address _initialOwner,
        address _superToken,
        address _flowImpl,
        address _manager,
        address _managerRewardPool,
        address _parent,
        FlowParams calldata _flowParams,
        RecipientMetadata calldata _metadata,
        IChainalysisSanctionsList _sanctionsOracle,
        bytes calldata _data
    ) public initializer {
        (, address erc721Token) = decodeInitializationData(_data);
        if (erc721Token == address(0)) revert ADDRESS_ZERO();

        erc721Votes = IERC721Checkpointable(erc721Token);

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

        emit ERC721VotingTokenChanged(erc721Token);
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
    ) external nonReentrant {
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
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function is virtual to allow for different deployment strategies in derived contracts
     * @param metadata The recipient's metadata like title, description, etc.
     * @param flowManager The address of the flow manager for the new contract
     * @param managerRewardPool The address of the manager reward pool for the new contract
     * @param initializationData The initialization data for the new contract
     * @return recipient address The address of the newly created Flow contract
     */
    function _deployFlowRecipient(
        RecipientMetadata calldata metadata,
        address flowManager,
        address managerRewardPool,
        bytes calldata initializationData
    ) internal override returns (address recipient) {
        bytes memory data = initializationData.length > 0
            ? initializationData
            : abi.encode(fs.flowImpl, address(erc721Votes));

        recipient = fs.deployFlowRecipient(
            metadata,
            flowManager,
            managerRewardPool,
            owner(),
            address(this),
            PERCENTAGE_SCALE,
            data
        );
    }

    /**
     * @notice Function to be called after updating the reward pool flow rate in Flow.sol
     * @dev This is used to update the rewards for ERC20 curators automatically when the flow rate changes
     */
    function _afterRewardPoolFlowUpdate(int96 newFlowRate) internal virtual override {
        address rewardPool = fs.managerRewardPool;
        if (rewardPool == address(0)) revert ADDRESS_ZERO();

        (bool shouldTransfer, uint256 transferAmount, uint256 balanceRequiredToStartFlow) = fs
            .calculateBufferAmountForRewardPool(rewardPool, address(this), newFlowRate);

        if (shouldTransfer) {
            fs.superToken.transfer(rewardPool, transferAmount);
        }

        // Call setFlowRate on the child contract
        // only set if buffer required is less than balance of contract
        if (balanceRequiredToStartFlow <= fs.superToken.balanceOf(rewardPool)) {
            IRewardPool(rewardPool).setFlowRate(getManagerRewardPoolFlowRate());
        }
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
     * @notice Decodes the initialization data
     * @param data The initialization data
     * @return flowImpl The address of the flow implementation for the deployed child contract
     * @return erc721Token The address of the ERC721 token used for voting
     */
    function decodeInitializationData(bytes calldata data) public pure returns (address flowImpl, address erc721Token) {
        (flowImpl, erc721Token) = abi.decode(data, (address, address));
    }
}
