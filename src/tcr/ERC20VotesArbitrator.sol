// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20VotesArbitrator } from "./interfaces/IERC20VotesArbitrator.sol";
import { IArbitrable } from "./interfaces/IArbitrable.sol";
import { ArbitratorStorageV1 } from "./storage/ArbitratorStorageV1.sol";

import { ERC20VotesMintable } from "../base/erc20/ERC20VotesMintable.sol";
import { ITCRFactory } from "./interfaces/ITCRFactory.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC20VotesArbitrator is
    IERC20VotesArbitrator,
    ArbitratorStorageV1,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    constructor() payable initializer {}

    /**
     * @notice Used to initialize the contract
     * @param initialOwner_ The address of the initial owner
     * @param votingToken_ The address of the ERC20 voting token
     * @param arbitrable_ The address of the arbitrable contract
     * @param votingPeriod_ The initial voting period
     * @param votingDelay_ The initial voting delay
     * @param revealPeriod_ The initial reveal period to reveal committed votes
     * @param arbitrationCost_ The initial arbitration cost
     */
    function initialize(
        address initialOwner_,
        address votingToken_,
        address arbitrable_,
        uint256 votingPeriod_,
        uint256 votingDelay_,
        uint256 revealPeriod_,
        uint256 arbitrationCost_
    ) public initializer {
        __Ownable2Step_init();
        __ReentrancyGuard_init();

        if (initialOwner_ == address(0)) revert INVALID_INITIAL_OWNER();
        if (arbitrable_ == address(0)) revert INVALID_ARBITRABLE_ADDRESS();
        if (votingToken_ == address(0)) revert INVALID_VOTING_TOKEN_ADDRESS();
        if (votingPeriod_ < MIN_VOTING_PERIOD || votingPeriod_ > MAX_VOTING_PERIOD) revert INVALID_VOTING_PERIOD();
        if (votingDelay_ < MIN_VOTING_DELAY || votingDelay_ > MAX_VOTING_DELAY) revert INVALID_VOTING_DELAY();
        if (revealPeriod_ < MIN_REVEAL_PERIOD || revealPeriod_ > MAX_REVEAL_PERIOD) revert INVALID_REVEAL_PERIOD();
        if (arbitrationCost_ < MIN_ARBITRATION_COST || arbitrationCost_ > MAX_ARBITRATION_COST)
            revert INVALID_ARBITRATION_COST();

        _transferOwnership(initialOwner_);

        emit VotingPeriodSet(_votingPeriod, votingPeriod_);
        emit VotingDelaySet(_votingDelay, votingDelay_);
        emit RevealPeriodSet(_revealPeriod, revealPeriod_);
        emit ArbitrationCostSet(_arbitrationCost, arbitrationCost_);

        votingToken = ERC20VotesMintable(votingToken_);
        arbitrable = IArbitrable(arbitrable_);
        _votingPeriod = votingPeriod_;
        _votingDelay = votingDelay_;
        _revealPeriod = revealPeriod_;
        _arbitrationCost = arbitrationCost_;
    }

    /**
     * @notice Function used to create a new dispute. Only callable by the arbitrable contract.
     * @param _choices The number of choices for the dispute
     * @param _extraData Additional data for the dispute
     * @return disputeID The ID of the new dispute
     */
    function createDispute(
        uint256 _choices,
        bytes calldata _extraData
    ) external onlyArbitrable nonReentrant returns (uint256 disputeID) {
        // only support 2 choices for now
        if (_choices != 2) revert INVALID_DISPUTE_CHOICES();

        // get tokens from arbitrable
        // arbitrable must have approved the arbitrator to transfer the tokens
        // fails otherwise
        IERC20(address(votingToken)).safeTransferFrom(address(arbitrable), address(this), _arbitrationCost);

        disputeCount++;
        Dispute storage newDispute = disputes[disputeCount];

        newDispute.id = disputeCount;
        newDispute.arbitrable = address(arbitrable);
        newDispute.currentRound = 0;
        newDispute.choices = _choices;
        newDispute.executed = false;

        newDispute.rounds[0].votingStartTime = block.timestamp + _votingDelay;
        newDispute.rounds[0].votingEndTime = newDispute.rounds[0].votingStartTime + _votingPeriod;
        newDispute.rounds[0].revealPeriodEndTime = newDispute.rounds[0].votingEndTime + _revealPeriod;
        newDispute.rounds[0].votes = 0; // total votes cast
        newDispute.rounds[0].ruling = IArbitrable.Party.None; // winning choice
        newDispute.rounds[0].extraData = _extraData;
        newDispute.rounds[0].creationBlock = block.number;
        newDispute.rounds[0].totalSupply = votingToken.totalSupply();
        newDispute.rounds[0].cost = _arbitrationCost;

        emit DisputeCreated(
            newDispute.id,
            address(arbitrable),
            newDispute.rounds[0].votingStartTime,
            newDispute.rounds[0].votingEndTime,
            newDispute.rounds[0].revealPeriodEndTime,
            newDispute.rounds[0].totalSupply,
            newDispute.rounds[0].creationBlock,
            newDispute.rounds[0].cost,
            _extraData,
            _choices
        );
        emit DisputeCreation(newDispute.id, arbitrable);

        return newDispute.id;
    }

    /**
     * @notice Gets the receipt for a voter on a given dispute
     * @param disputeId the id of dispute
     * @param voter The address of the voter
     * @return The voting receipt
     */
    function getReceipt(uint256 disputeId, address voter) external view returns (Receipt memory) {
        uint256 round = disputes[disputeId].currentRound;
        return disputes[disputeId].rounds[round].receipts[voter];
    }

    /**
     * @notice Gets the receipt for a voter on a given dispute and round
     * @param disputeId The id of dispute
     * @param round The round number
     * @param voter The address of the voter
     * @return The voting receipt for the specified round
     */
    function getReceiptByRound(uint256 disputeId, uint256 round, address voter) external view returns (Receipt memory) {
        require(disputeId <= disputeCount, "Invalid dispute ID");
        require(round <= disputes[disputeId].currentRound, "Invalid round");
        return disputes[disputeId].rounds[round].receipts[voter];
    }

    /**
     * @notice Gets the state of a dispute
     * @param disputeId The id of the dispute
     * @return Dispute state
     */
    function currentRoundState(uint256 disputeId) external view returns (DisputeState) {
        return _getVotingRoundState(disputeId, disputes[disputeId].currentRound);
    }

    /**
     * @notice Gets the votes for a specific choice and the total votes in a given round of a dispute
     * @param disputeId The ID of the dispute
     * @param round The round number
     * @param choice The choice number to get votes for
     * @return choiceVotes The number of votes for the specified choice
     */
    function getVotesByRound(
        uint256 disputeId,
        uint256 round,
        uint256 choice
    ) external view returns (uint256 choiceVotes) {
        require(disputeId <= disputeCount, "Invalid dispute ID");
        require(round <= disputes[disputeId].currentRound, "Invalid round");
        require(choice <= disputes[disputeId].choices, "Invalid choice");

        VotingRound storage votingRound = disputes[disputeId].rounds[round];
        choiceVotes = votingRound.choiceVotes[choice];
    }

    /**
     * @notice Gets the total votes in a given round of a dispute
     * @param disputeId The ID of the dispute
     * @param round The round number
     * @return totalVotes The total number of votes cast in the specified round
     */
    function getTotalVotesByRound(uint256 disputeId, uint256 round) external view returns (uint256 totalVotes) {
        require(disputeId <= disputeCount, "Invalid dispute ID");
        require(round <= disputes[disputeId].currentRound, "Invalid round");

        VotingRound storage votingRound = disputes[disputeId].rounds[round];
        totalVotes = votingRound.votes;
    }

    /**
     * @notice Get the state of a specific voting round for a dispute
     * @param disputeId The ID of the dispute
     * @param round The round number
     * @return The state of the voting round
     */
    function _getVotingRoundState(
        uint256 disputeId,
        uint256 round
    ) internal view validDisputeID(disputeId) returns (DisputeState) {
        VotingRound storage votingRound = disputes[disputeId].rounds[round];

        if (block.timestamp < votingRound.votingStartTime) {
            return DisputeState.Pending;
        } else if (block.timestamp < votingRound.votingEndTime) {
            return DisputeState.Active;
        } else if (block.timestamp < votingRound.revealPeriodEndTime) {
            return DisputeState.Reveal;
        } else {
            return DisputeState.Solved;
        }
    }

    /**
     * @notice Get the status of a dispute
     * @dev This function maps the DisputeState to the IArbitrator.DisputeStatus
     * @param disputeId The ID of the dispute to check
     * @return The status of the dispute as defined in IArbitrator.DisputeStatus
     * @dev checks for valid dispute ID first in the state function
     */
    function disputeStatus(uint256 disputeId) public view returns (DisputeStatus) {
        DisputeState disputeState = _getVotingRoundState(disputeId, disputes[disputeId].currentRound);

        if (disputeState == DisputeState.Solved) {
            // executed or solved
            return DisputeStatus.Solved;
        } else {
            // pending, active, reveal voting states
            return DisputeStatus.Waiting;
        }
    }

    /**
     * @notice Returns the current ruling for a dispute.
     * @param disputeId The ID of the dispute.
     * @return ruling The current ruling of the dispute.
     */
    function currentRuling(
        uint256 disputeId
    ) external view override validDisputeID(disputeId) returns (IArbitrable.Party) {
        uint256 round = disputes[disputeId].currentRound;
        return disputes[disputeId].rounds[round].ruling;
    }

    /**
     * @notice Cast a vote for a dispute
     * @param disputeId The id of the dispute to vote on
     * @param commitHash Commit keccak256 hash of voter's choice, reason (optional) and salt (in this order)
     */
    function commitVote(uint256 disputeId, bytes32 commitHash) external nonReentrant {
        _commitVoteInternal(msg.sender, disputeId, commitHash);

        emit VoteCommitted(msg.sender, disputeId, commitHash);
    }

    /**
     * @notice Reveal a previously committed vote for a dispute
     * @param disputeId The id of the dispute to reveal the vote for
     * @param voter The address of the voter. Added for custodial voting.
     * @param choice The choice that was voted for
     * @param reason The reason for the vote
     * @param salt The salt used in the commit phase
     */
    function revealVote(
        uint256 disputeId,
        address voter,
        uint256 choice,
        string calldata reason,
        bytes32 salt
    ) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];
        uint256 round = dispute.currentRound;

        if (_getVotingRoundState(disputeId, round) != DisputeState.Reveal) revert VOTING_CLOSED();
        if (choice == 0 || choice > dispute.choices) revert INVALID_VOTE_CHOICE();

        Receipt storage receipt = dispute.rounds[round].receipts[voter];
        if (!receipt.hasCommitted) revert NO_COMMITTED_VOTE();
        if (receipt.hasRevealed) revert ALREADY_REVEALED_VOTE();

        // Reconstruct the hash to verify the revealed vote
        bytes32 reconstructedHash = keccak256(abi.encode(choice, reason, salt));
        if (reconstructedHash != receipt.commitHash) revert HASHES_DO_NOT_MATCH();

        uint256 votes = votingToken.getPastVotes(voter, dispute.rounds[round].creationBlock);

        if (votes == 0) revert VOTER_HAS_NO_VOTES();

        receipt.hasRevealed = true;
        receipt.choice = choice;
        receipt.votes = votes;

        dispute.rounds[round].votes += votes;
        dispute.rounds[round].choiceVotes[choice] += votes;

        emit VoteRevealed(voter, disputeId, receipt.commitHash, choice, reason, votes);
    }

    /**
     * @notice Internal function that caries out voting commitment logic
     * @param voter The voter that is casting their vote
     * @param disputeId The id of the dispute to vote on
     * @param commitHash The keccak256 hash of the voter's choice, reason (optional) and salt (in this order)
     */
    function _commitVoteInternal(address voter, uint256 disputeId, bytes32 commitHash) internal {
        Dispute storage dispute = disputes[disputeId];
        uint256 round = dispute.currentRound;

        if (_getVotingRoundState(disputeId, round) != DisputeState.Active) revert VOTING_CLOSED();

        Receipt storage receipt = dispute.rounds[round].receipts[voter];
        if (receipt.hasCommitted) revert VOTER_ALREADY_VOTED();
        uint256 votes = votingToken.getPastVotes(voter, dispute.rounds[round].creationBlock);

        if (votes == 0) revert VOTER_HAS_NO_VOTES();

        receipt.hasCommitted = true;
        receipt.commitHash = commitHash;
    }

    /**
     * @notice Checks if a voter can vote in a specific round
     * @param disputeId The ID of the dispute
     * @param round The round number
     * @param voter The address of the voter
     * @return votingPower The voting power of the voter in the round
     * @return canVote True if the voter can vote in the round, false otherwise
     */
    function votingPowerInRound(uint256 disputeId, uint256 round, address voter) public view returns (uint256, bool) {
        Dispute storage dispute = disputes[disputeId];
        VotingRound storage votingRound = dispute.rounds[round];
        uint256 votes = votingToken.getPastVotes(voter, votingRound.creationBlock);

        return (votes, votes > 0);
    }

    /**
     * @notice Checks if a voter can vote in the current round
     * @param disputeId The ID of the dispute
     * @param voter The address of the voter
     * @return votingPower The voting power of the voter in the current round
     * @return canVote True if the voter can vote in the current round, false otherwise
     */
    function votingPowerInCurrentRound(uint256 disputeId, address voter) public view returns (uint256, bool) {
        return votingPowerInRound(disputeId, disputes[disputeId].currentRound, voter);
    }

    /**
     * @notice Execute a dispute and set the ruling
     * @param disputeId The ID of the dispute to execute
     */
    function executeRuling(uint256 disputeId) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];
        uint256 round = dispute.currentRound;
        if (dispute.executed) revert DISPUTE_ALREADY_EXECUTED();
        if (_getVotingRoundState(disputeId, round) != DisputeState.Solved) revert DISPUTE_NOT_SOLVED();

        uint256 winningChoice = _determineWinningChoice(disputeId, round);

        // Convert winning choice to Party enum
        IArbitrable.Party ruling = _convertChoiceToParty(winningChoice);

        dispute.rounds[round].ruling = ruling;
        dispute.executed = true;
        dispute.winningChoice = winningChoice;

        // Call the rule function on the arbitrable contract
        arbitrable.rule(disputeId, uint256(ruling));

        emit DisputeExecuted(disputeId, ruling);
    }

    /**
     * @notice Allows voters to view their proportional share of the cost for a voting round if they voted on the correct side.
     * @param disputeId The ID of the dispute.
     * @param round The round number.
     * @param voter The address of the voter.
     * @return The amount of rewards the voter is entitled to.
     */
    function getRewardsForRound(uint256 disputeId, uint256 round, address voter) external view returns (uint256) {
        Dispute storage dispute = disputes[disputeId];
        VotingRound storage votingRound = dispute.rounds[round];
        Receipt storage receipt = votingRound.receipts[voter];

        if (round > dispute.currentRound) revert INVALID_ROUND();

        // Ensure the dispute round is finalized
        if (_getVotingRoundState(disputeId, round) != DisputeState.Solved) return 0;

        // If no votes were cast, return 0
        if (votingRound.votes == 0) return 0;

        // Check that the voter has voted
        if (!receipt.hasRevealed) return 0;

        // Check that the voter hasn't already claimed
        if (votingRound.rewardsClaimed[voter]) return 0;

        uint256 winningChoice = _determineWinningChoice(disputeId, round);

        uint256 amount = 0;
        uint256 totalRewards = votingRound.cost; // Total amount to distribute among voters

        if (winningChoice == 0) {
            // Ruling is 0 or Party.None, both sides can withdraw proportional share
            amount = (receipt.votes * totalRewards) / votingRound.votes;
        } else {
            // Ruling is not 0, only winning voters can withdraw
            if (receipt.choice != winningChoice) {
                return 0;
            }
            uint256 totalWinningVotes = votingRound.choiceVotes[winningChoice];

            if (totalWinningVotes == 0) return 0;

            // Calculate voter's share
            amount = (receipt.votes * totalRewards) / totalWinningVotes;
        }

        return amount;
    }

    /**
     * @notice Allows the owner to withdraw the rewards for a round if there were no votes in the round
     * @notice Owner can reimburse applicants, or burn the tokens etc.
     * @param disputeId The ID of the dispute.
     * @param round The round number.
     */
    function withdrawRewardsForInvalidRound(uint256 disputeId, uint256 round) external onlyOwner {
        Dispute storage dispute = disputes[disputeId];
        VotingRound storage votingRound = dispute.rounds[round];
        uint256 totalRewards = votingRound.cost; // Total amount to distribute among voters

        if (round > dispute.currentRound) revert INVALID_ROUND();

        // Ensure the dispute round is finalized
        if (_getVotingRoundState(disputeId, round) != DisputeState.Solved) {
            revert DISPUTE_NOT_SOLVED();
        }

        if (votingRound.votes > 0) revert VOTES_WERE_CAST();

        IERC20(address(votingToken)).safeTransfer(owner(), totalRewards);
    }

    /**
     * @notice Allows voters to withdraw their proportional share of the cost for a voting round if they voted on the correct side of the ruling.
     * @param disputeId The ID of the dispute.
     * @param round The round number.
     * @param voter The address of the voter.
     */
    function withdrawVoterRewards(uint256 disputeId, uint256 round, address voter) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];

        // Get the voting round
        VotingRound storage votingRound = dispute.rounds[round];

        if (round > dispute.currentRound) revert INVALID_ROUND();

        // Ensure the dispute round is finalized
        if (_getVotingRoundState(disputeId, round) != DisputeState.Solved) {
            revert DISPUTE_NOT_SOLVED();
        }

        // Check that the voter hasn't already claimed
        if (votingRound.rewardsClaimed[voter]) {
            revert REWARD_ALREADY_CLAIMED();
        }

        // Get the receipt for the voter
        Receipt storage receipt = votingRound.receipts[voter];

        // Check that the voter has voted
        if (!receipt.hasRevealed) {
            revert VOTER_HAS_NOT_VOTED();
        }

        uint256 winningChoice = _determineWinningChoice(disputeId, round);

        uint256 amount = 0;
        uint256 totalRewards = votingRound.cost; // Total amount to distribute among voters

        if (votingRound.votes == 0) revert NO_VOTES();

        if (winningChoice == 0) {
            // Ruling is 0 or Party.None, both sides can withdraw proportional share
            amount = (receipt.votes * totalRewards) / votingRound.votes;
        } else {
            // Ruling is not 0, only winning voters can withdraw
            if (receipt.choice != winningChoice) {
                revert VOTER_ON_LOSING_SIDE();
            }
            uint256 totalWinningVotes = votingRound.choiceVotes[winningChoice];

            if (totalWinningVotes == 0) revert NO_WINNING_VOTES();

            // Calculate voter's share
            amount = (receipt.votes * totalRewards) / totalWinningVotes;
        }

        // Mark as claimed
        votingRound.rewardsClaimed[voter] = true;

        // Transfer tokens to voter
        IERC20(address(votingToken)).safeTransfer(voter, amount);

        emit RewardWithdrawn(disputeId, round, voter, amount);
    }

    /**
     * @notice Determines the winning choice based on the votes.
     * @param _disputeID The ID of the dispute.
     * @param _round The round number.
     * @return The choice with the highest votes.
     */
    function _determineWinningChoice(uint256 _disputeID, uint256 _round) internal view returns (uint256) {
        Dispute storage dispute = disputes[_disputeID];
        VotingRound storage votingRound = dispute.rounds[_round];

        uint256 winningChoice = 0;
        uint256 highestVotes = 0;
        bool tie = false;

        for (uint256 i = 1; i <= dispute.choices; i++) {
            uint256 votesForChoice = votingRound.choiceVotes[i];
            if (votesForChoice > highestVotes) {
                highestVotes = votesForChoice;
                winningChoice = i;
                tie = false; // reset tie since we have a new outright leader
            } else if (votesForChoice == highestVotes && votesForChoice != 0) {
                tie = true;
            }
        }

        if (tie) {
            return 0;
        }

        return winningChoice;
    }

    /**
     * @notice Converts a choice number to the corresponding Party enum.
     * @param _choice The choice number.
     * @return The corresponding Party.
     */
    function _convertChoiceToParty(uint256 _choice) internal pure returns (IArbitrable.Party) {
        if (_choice == 0) {
            return IArbitrable.Party.None;
        } else if (_choice == 1) {
            return IArbitrable.Party.Requester;
        } else if (_choice == 2) {
            return IArbitrable.Party.Challenger;
        } else {
            return IArbitrable.Party.None;
        }
    }

    /**
     * @dev Returns the arbitrator parameters for use in the TCR factory.
     * @return ArbitratorParams struct containing the necessary parameters for the factory.
     */
    function getArbitratorParamsForFactory() external view override returns (ITCRFactory.ArbitratorParams memory) {
        return
            ITCRFactory.ArbitratorParams({
                votingPeriod: _votingPeriod,
                votingDelay: _votingDelay,
                revealPeriod: _revealPeriod,
                arbitrationCost: _arbitrationCost
            });
    }

    /**
     * @notice Owner function for setting the voting delay
     * @param newVotingDelay new voting delay, in blocks
     */
    function setVotingDelay(uint256 newVotingDelay) external onlyOwner {
        if (newVotingDelay < MIN_VOTING_DELAY || newVotingDelay > MAX_VOTING_DELAY) revert INVALID_VOTING_DELAY();
        uint256 oldVotingDelay = _votingDelay;
        _votingDelay = newVotingDelay;

        emit VotingDelaySet(oldVotingDelay, _votingDelay);
    }

    /**
     * @notice Owner function for setting the reveal period
     * @param newRevealPeriod new reveal period, in blocks
     */
    function setRevealPeriod(uint256 newRevealPeriod) external onlyOwner {
        if (newRevealPeriod < MIN_REVEAL_PERIOD || newRevealPeriod > MAX_REVEAL_PERIOD) revert INVALID_REVEAL_PERIOD();
        uint256 oldRevealPeriod = _revealPeriod;
        _revealPeriod = newRevealPeriod;

        emit RevealPeriodSet(oldRevealPeriod, _revealPeriod);
    }

    /**
     * @notice Owner function for setting the arbitration cost
     * @param newArbitrationCost new arbitration cost, in wei
     */
    function setArbitrationCost(uint256 newArbitrationCost) external onlyOwner {
        uint256 oldArbitrationCost = _arbitrationCost;
        _arbitrationCost = newArbitrationCost;

        emit ArbitrationCostSet(oldArbitrationCost, _arbitrationCost);
    }

    /**
     * @notice Owner function for setting the voting period
     * @param newVotingPeriod new voting period, in blocks
     */
    function setVotingPeriod(uint256 newVotingPeriod) external onlyOwner {
        if (newVotingPeriod < MIN_VOTING_PERIOD || newVotingPeriod > MAX_VOTING_PERIOD) revert INVALID_VOTING_PERIOD();

        uint256 oldVotingPeriod = _votingPeriod;
        _votingPeriod = newVotingPeriod;

        emit VotingPeriodSet(oldVotingPeriod, _votingPeriod);
    }

    function bps2Uint(uint256 bps, uint256 number) internal pure returns (uint256) {
        return (number * bps) / 10000;
    }

    /**
     * @notice Modifier to restrict function access to only the arbitrable contract
     */
    modifier onlyArbitrable() {
        if (msg.sender != address(arbitrable)) revert ONLY_ARBITRABLE();
        _;
    }

    /**
     * @notice Modifier to check if a dispute ID is valid
     * @param _disputeID The ID of the dispute to check
     */
    modifier validDisputeID(uint256 _disputeID) {
        if (_disputeID == 0 || _disputeID > disputeCount) revert INVALID_DISPUTE_ID();
        _;
    }

    /**
     * @notice Returns the cost of arbitration
     * @return cost The cost of arbitration
     */
    function arbitrationCost(bytes calldata) external view override returns (uint256 cost) {
        return _arbitrationCost;
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param _newImpl The new implementation address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
