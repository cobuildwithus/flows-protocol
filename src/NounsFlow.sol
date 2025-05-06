// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { Flow } from "./Flow.sol";
import { INounsFlow } from "./interfaces/IFlow.sol";
import { ITokenVerifier } from "./interfaces/ITokenVerifier.sol";
import { IStateProof } from "./interfaces/IStateProof.sol";
import { IRewardPool } from "./interfaces/IRewardPool.sol";
import { FlowVotes } from "./library/FlowVotes.sol";
import { FlowRates } from "./library/FlowRates.sol";
import { NounsFlowLibrary } from "./library/NounsFlowLibrary.sol";
import { IChainalysisSanctionsList } from "./interfaces/external/chainalysis/IChainalysisSanctionsList.sol";

contract NounsFlow is INounsFlow, Flow {
    using FlowVotes for Storage;
    using FlowRates for Storage;
    using NounsFlowLibrary for Storage;

    ITokenVerifier public verifier;

    constructor() payable initializer {}

    function initialize(
        address _initialOwner,
        address _verifier,
        address _superToken,
        address _flowImpl,
        address _manager,
        address _managerRewardPool,
        address _parent,
        FlowParams calldata _flowParams,
        RecipientMetadata calldata _metadata,
        IChainalysisSanctionsList _sanctionsOracle
    ) public initializer {
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

        verifier = ITokenVerifier(_verifier);
    }

    /**
     * @notice Cast votes for multiple token owners across multiple tokens.
     * @param owners An array of token owner addresses.
     * @param tokenIds A 2D array of token IDs, where each inner array corresponds to an owner.
     * @param recipientIds An array of recipient IDs for the grant recipients.
     * @param percentAllocations An array of basis points allocations for each recipient.
     * @param baseProofParams The base state proof parameters.
     * @param ownershipStorageProofs A 2D array of storage proofs for token ownership, corresponding to each token ID.
     * @param delegateStorageProofs A 2D array of storage proofs for delegation, corresponding to each token ID.
     */
    function castVotes(
        address[] calldata owners,
        uint256[][] calldata tokenIds,
        bytes32[] calldata recipientIds,
        uint32[] calldata percentAllocations,
        IStateProof.BaseParameters calldata baseProofParams,
        bytes[][][] calldata ownershipStorageProofs,
        bytes[][] calldata delegateStorageProofs
    ) external nonReentrant {
        fs.validateAllocations(recipientIds, percentAllocations, PERCENTAGE_SCALE);

        uint256 totalFlowsToUpdate = 0;
        bool shouldUpdateFlowRate = false;

        // if the timestamp is more than 5 minutes old, it is invalid
        if (baseProofParams.beaconOracleTimestamp < block.timestamp - 5 minutes) revert PAST_PROOF();

        for (uint256 i = 0; i < owners.length; i++) {
            (uint256 flowsToUpdate, bool updateFlowRate) = _castVotesForOwner(
                owners[i],
                tokenIds[i],
                recipientIds,
                percentAllocations,
                _generateOwnershipProofs(baseProofParams, ownershipStorageProofs[i]),
                _generateStateProofParams(baseProofParams, delegateStorageProofs[i])
            );
            totalFlowsToUpdate += flowsToUpdate;
            shouldUpdateFlowRate = shouldUpdateFlowRate || updateFlowRate;
        }

        _afterVotesCast(recipientIds, totalFlowsToUpdate, shouldUpdateFlowRate);
    }

    /**
     * @notice Cast votes for a set of grant addresses on behalf of a token owner
     * @param owner The address of the token owner
     * @param tokenIds The token IDs that the owner is using to vote
     * @param recipientIds The recipient IDs of the grant recipients
     * @param percentAllocations The basis points of the vote to be split among the recipients
     * @param ownershipProofs The state proofs for token ownership
     * @param delegateProof The state proof for delegation
     */
    function _castVotesForOwner(
        address owner,
        uint256[] calldata tokenIds,
        bytes32[] calldata recipientIds,
        uint32[] calldata percentAllocations,
        IStateProof.Parameters[] memory ownershipProofs,
        IStateProof.Parameters memory delegateProof
    ) internal returns (uint256 totalFlowsToUpdate, bool shouldUpdateFlowRate) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (!verifier.canVoteWithToken(tokenIds[i], owner, msg.sender, ownershipProofs[i], delegateProof)) {
                revert NOT_ABLE_TO_VOTE_WITH_TOKEN();
            }
            (uint256 flowsToUpdate, bool updateFlowRate) = _setVotesAllocationForTokenId(
                tokenIds[i],
                recipientIds,
                percentAllocations,
                msg.sender
            );
            totalFlowsToUpdate += flowsToUpdate;
            shouldUpdateFlowRate = shouldUpdateFlowRate || updateFlowRate;
        }
    }

    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function overrides the base _deployFlowRecipient to use NounsFlow-specific initialization
     * @param metadata The recipient's metadata like title, description, etc.
     * @param flowManager The address of the flow manager for the new contract
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
            address(verifier),
            owner(),
            address(this),
            1e6 // idk what is going on here but i cannot verify contract on etherscan if this is PERCENTAGE_SCALE
        );
    }

    /**
     * @notice Generates an array of ownership proofs for multiple token IDs
     * @dev This function creates state proof parameters for each token ID using the base parameters and storage proofs
     * @param baseProofParams The base state proof parameters common to all proofs
     * @param ownershipStorageProofs A 2D array of storage proofs, where each inner array corresponds to a token ID
     * @return An array of IStateProof.Parameters, one for each token ID
     */
    function _generateOwnershipProofs(
        IStateProof.BaseParameters calldata baseProofParams,
        bytes[][] calldata ownershipStorageProofs
    ) internal pure returns (IStateProof.Parameters[] memory) {
        uint256 tokenIdCount = ownershipStorageProofs.length;
        IStateProof.Parameters[] memory ownershipProofs = new IStateProof.Parameters[](tokenIdCount);

        for (uint256 j = 0; j < tokenIdCount; j++) {
            // there is one storage proof for each tokenId
            ownershipProofs[j] = _generateStateProofParams(baseProofParams, ownershipStorageProofs[j]);
        }

        return ownershipProofs;
    }

    /**
     * @notice Generates StateProofParameters from base parameters and storage proof
     * @param baseProofParams The base state proof parameters
     * @param storageProof The storage proof for the specific state
     * @return IStateProof.Parameters The generated state proof parameters
     */
    function _generateStateProofParams(
        IStateProof.BaseParameters calldata baseProofParams,
        bytes[] calldata storageProof
    ) internal pure returns (IStateProof.Parameters memory) {
        return
            IStateProof.Parameters({
                beaconRoot: baseProofParams.beaconRoot,
                beaconOracleTimestamp: baseProofParams.beaconOracleTimestamp,
                executionStateRoot: baseProofParams.executionStateRoot,
                stateRootProof: baseProofParams.stateRootProof,
                accountProof: baseProofParams.accountProof,
                storageProof: storageProof
            });
    }

    /**
     * @notice Function to be called after updating the reward pool flow rate in Flow.sol
     * @dev This is used to update the rewards for ERC20 curators automatically when the flow rate changes
     * @param newFlowRate The new flow rate to the reward pool
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
     * @notice Updates the token verifier address
     * @dev Can only be called by the contract owner
     * @param _verifier The new verifier address
     */
    function updateVerifier(address _verifier) external onlyOwner {
        if (_verifier == address(0)) revert ADDRESS_ZERO();
        verifier = ITokenVerifier(_verifier);
    }

    /**
     * @notice Function to calculate the total vote weight based on days since August 8th, 2021
     * @dev Assumes one noun minted per day since August 8th, 2021
     * @dev Every 10th noun is automatically minted to founders without additional time delay
     * @return uint256 The total vote weight calculated from days elapsed
     */
    function totalTokenSupplyVoteWeight() public view override returns (uint256) {
        uint256 firstAuctionStartSeconds = 1628399590;
        uint256 daysSinceStart = (block.timestamp - firstAuctionStartSeconds) / 1 days;
        // +1 because the first auction started on 8th August 2021
        // and also minted the 0th noun that day
        uint256 founderNouns = (daysSinceStart / 10) + 1;
        uint256 totalNouns = daysSinceStart + founderNouns;
        return totalNouns * fs.tokenVoteWeight;
    }
}
