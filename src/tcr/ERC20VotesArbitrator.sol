// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20VotesArbitrator } from "./interfaces/IERC20VotesArbitrator.sol";
import { IArbitrable } from "./interfaces/IArbitrable.sol";
import { ArbitratorStorageV1 } from "./storage/ArbitratorStorageV1.sol";

import { ERC20VotesMintable } from "../ERC20VotesMintable.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract ERC20VotesArbitrator is
    IERC20VotesArbitrator,
    ArbitratorStorageV1,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    constructor() payable initializer {}

    /**
     * @notice Used to initialize the contract
     * @param votingToken_ The address of the ERC20 voting token
     * @param arbitrable_ The address of the arbitrable contract
     * @param votingPeriod_ The initial voting period
     * @param votingDelay_ The initial voting delay
     * @param revealPeriod_ The initial reveal period to reveal committed votes
     * @param appealPeriod_ The initial appeal period
     * @param appealCost_ The initial appeal cost
     * @param arbitrationCost_ The initial arbitration cost
     * @param quorumVotesBPS_ The initial quorum votes threshold in basis points
     */
    function initialize(
        address votingToken_,
        address arbitrable_,
        uint256 votingPeriod_,
        uint256 votingDelay_,
        uint256 revealPeriod_,
        uint256 appealPeriod_,
        uint256 appealCost_,
        uint256 quorumVotesBPS_,
        uint256 arbitrationCost_
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        if (votingToken_ == address(0)) revert INVALID_VOTING_TOKEN_ADDRESS();
        if (votingPeriod_ < MIN_VOTING_PERIOD || votingPeriod_ > MAX_VOTING_PERIOD) revert INVALID_VOTING_PERIOD();
        if (votingDelay_ < MIN_VOTING_DELAY || votingDelay_ > MAX_VOTING_DELAY) revert INVALID_VOTING_DELAY();
        if (quorumVotesBPS_ < MIN_QUORUM_VOTES_BPS || quorumVotesBPS_ > MAX_QUORUM_VOTES_BPS)
            revert INVALID_QUORUM_VOTES_BPS();
        if (revealPeriod_ < MIN_REVEAL_PERIOD || revealPeriod_ > MAX_REVEAL_PERIOD) revert INVALID_REVEAL_PERIOD();
        if (appealPeriod_ < MIN_APPEAL_PERIOD || appealPeriod_ > MAX_APPEAL_PERIOD) revert INVALID_APPEAL_PERIOD();
        if (appealCost_ < MIN_APPEAL_COST || appealCost_ > MAX_APPEAL_COST) revert INVALID_APPEAL_COST();
        if (arbitrationCost_ < MIN_ARBITRATION_COST || arbitrationCost_ > MAX_ARBITRATION_COST)
            revert INVALID_ARBITRATION_COST();

        emit VotingPeriodSet(votingPeriod, votingPeriod_);
        emit VotingDelaySet(votingDelay, votingDelay_);
        emit QuorumVotesBPSSet(quorumVotesBPS, quorumVotesBPS_);
        emit AppealPeriodSet(_appealPeriod, appealPeriod_);
        emit AppealCostSet(_appealCost, appealCost_);
        emit ArbitrationCostSet(_arbitrationCost, arbitrationCost_);

        votingToken = ERC20VotesMintable(votingToken_);
        arbitrable = IArbitrable(arbitrable_);
        votingPeriod = votingPeriod_;
        votingDelay = votingDelay_;
        quorumVotesBPS = quorumVotesBPS_;
        revealPeriod = revealPeriod_;
        _appealPeriod = appealPeriod_;
        _appealCost = appealCost_;
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
    ) external onlyArbitrable returns (uint256 disputeID) {
        disputeCount++;
        Dispute storage newDispute = disputes[disputeCount];

        newDispute.id = disputeCount;
        newDispute.arbitrable = address(arbitrable);
        newDispute.currentRound = 0;
        newDispute.choices = _choices;
        newDispute.executed = false;

        newDispute.rounds[0].votingStartTime = block.timestamp + votingDelay;
        newDispute.rounds[0].votingEndTime = newDispute.rounds[0].votingStartTime + votingPeriod;
        newDispute.rounds[0].revealPeriodEndTime = newDispute.rounds[0].votingEndTime + revealPeriod;
        newDispute.rounds[0].appealPeriodEndTime = newDispute.rounds[0].revealPeriodEndTime + _appealPeriod;
        newDispute.rounds[0].votes = 0; // total votes cast
        newDispute.rounds[0].ruling = IArbitrable.Party.None; // winning choice
        newDispute.rounds[0].extraData = _extraData;
        newDispute.rounds[0].creationBlock = block.number;
        newDispute.rounds[0].quorumVotes = quorumVotes();
        newDispute.rounds[0].totalSupply = votingToken.totalSupply();

        emit DisputeCreated(
            newDispute.id,
            address(arbitrable),
            newDispute.rounds[0].votingStartTime,
            newDispute.rounds[0].votingEndTime,
            newDispute.rounds[0].revealPeriodEndTime,
            newDispute.rounds[0].appealPeriodEndTime,
            newDispute.rounds[0].quorumVotes,
            newDispute.rounds[0].totalSupply,
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
     * @notice Gets the state of a dispute
     * @param disputeId The id of the dispute
     * @return Dispute state
     */
    function state(uint256 disputeId) public view validDisputeID(disputeId) returns (DisputeState) {
        Dispute storage dispute = disputes[disputeId];
        uint256 round = dispute.currentRound;
        if (block.timestamp <= dispute.rounds[round].votingStartTime) {
            return DisputeState.Pending;
        } else if (block.timestamp <= dispute.rounds[round].votingEndTime) {
            return DisputeState.Active;
        } else if (block.timestamp <= dispute.rounds[round].revealPeriodEndTime) {
            return DisputeState.Reveal;
        } else if (block.timestamp <= dispute.rounds[round].appealPeriodEndTime) {
            return DisputeState.Appealable;
        } else if (dispute.rounds[round].votes < dispute.rounds[round].quorumVotes) {
            return DisputeState.QuorumNotReached;
        } else if (dispute.executed) {
            return DisputeState.Executed;
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
        DisputeState disputeState = state(disputeId);

        if (disputeState == DisputeState.Appealable || disputeState == DisputeState.QuorumNotReached) {
            return DisputeStatus.Appealable;
        } else if (disputeState == DisputeState.Executed || disputeState == DisputeState.Solved) {
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
     * @param choice The support value for the vote. Based on the choices provided in the createDispute function
     */
    function castVote(uint256 disputeId, uint8 choice) external {
        emit VoteCast(msg.sender, disputeId, choice, _castVoteInternal(msg.sender, disputeId, choice), "");
    }

    /**
     * @notice Cast a vote for a dispute with a reason
     * @param disputeId The id of the dispute to vote on
     * @param choice The support value for the vote. Based on the choices provided in the createDispute function
     * @param reason The reason given for the vote by the voter
     */
    function castVoteWithReason(uint256 disputeId, uint8 choice, string calldata reason) external {
        emit VoteCast(msg.sender, disputeId, choice, _castVoteInternal(msg.sender, disputeId, choice), reason);
    }

    /**
     * @notice Internal function that caries out voting logic
     * @param voter The voter that is casting their vote
     * @param disputeId The id of the dispute to vote on
     * @param choice The support value for the vote. Based on the choices provided in the createDispute function
     * @return The number of votes cast
     */
    function _castVoteInternal(address voter, uint256 disputeId, uint256 choice) internal returns (uint256) {
        if (state(disputeId) != DisputeState.Active) revert VOTING_CLOSED();
        if (choice > disputes[disputeId].choices) revert INVALID_VOTE_CHOICE();
        Dispute storage dispute = disputes[disputeId];
        uint256 round = dispute.currentRound;
        Receipt storage receipt = dispute.rounds[round].receipts[voter];
        if (receipt.hasVoted) revert VOTER_ALREADY_VOTED();
        uint256 votes = votingToken.getPastVotes(voter, dispute.rounds[round].creationBlock);

        dispute.rounds[round].votes += votes;

        dispute.rounds[round].choiceVotes[choice] += votes;

        receipt.hasVoted = true;
        receipt.choice = choice;
        receipt.votes = votes;

        return votes;
    }

    /**
     * @notice Implements the appeal process for disputes within the ERC20VotesArbitrator.
     * @param _disputeID The ID of the dispute to appeal.
     */
    function appeal(uint256 _disputeID, bytes calldata) external payable override onlyArbitrable nonReentrant {
        Dispute storage dispute = disputes[_disputeID];

        // Ensure the dispute exists and is in a state that allows appeals
        if (disputeStatus(_disputeID) != DisputeStatus.Appealable) revert DISPUTE_NOT_APPEALABLE();
        if (block.timestamp >= dispute.rounds[dispute.currentRound].appealPeriodEndTime) revert APPEAL_PERIOD_ENDED();

        // Calculate the appeal cost
        uint256 newRound = dispute.currentRound + 1;
        uint256 costToAppeal = _calculateAppealCost(newRound);

        // todo transfer erc20 tokens to address(this)

        emit AppealDecision(_disputeID, arbitrable);
        emit AppealRaised(_disputeID, newRound, msg.sender, costToAppeal);

        emit DisputeReset(
            _disputeID,
            dispute.rounds[newRound].votingStartTime,
            dispute.rounds[newRound].votingEndTime,
            dispute.rounds[newRound].revealPeriodEndTime,
            dispute.rounds[newRound].appealPeriodEndTime,
            dispute.rounds[newRound].quorumVotes,
            dispute.rounds[newRound].totalSupply,
            dispute.rounds[newRound].extraData
        );

        dispute.rounds[newRound].votingStartTime = block.timestamp + votingDelay;
        dispute.rounds[newRound].votingEndTime = dispute.rounds[newRound].votingStartTime + votingPeriod;
        dispute.rounds[newRound].revealPeriodEndTime = dispute.rounds[newRound].votingEndTime + revealPeriod;
        dispute.rounds[newRound].appealPeriodEndTime = dispute.rounds[newRound].revealPeriodEndTime + _appealPeriod;
        dispute.rounds[newRound].votes = 0;
        dispute.rounds[newRound].ruling = IArbitrable.Party.None;
        dispute.rounds[newRound].creationBlock = block.number;
        dispute.rounds[newRound].quorumVotes = quorumVotes();
        dispute.rounds[newRound].totalSupply = votingToken.totalSupply();
        dispute.currentRound = newRound;

        dispute.appeals.push(
            Appeal({
                roundNumber: newRound,
                arbitrable: dispute.arbitrable,
                disputeID: _disputeID,
                appealCost: costToAppeal,
                appealedAt: block.timestamp
            })
        );
    }

    /**
     * @notice Calculates the cost required to appeal a specific dispute.
     * @param _currentRound The current round number of the dispute.
     * @return The calculated appeal cost.
     */
    function _calculateAppealCost(uint256 _currentRound) internal view returns (uint256) {
        // Increase the appeal cost with each round
        return _appealCost * (2 ** (_currentRound));
    }

    /**
     * @notice Execute a dispute and set the ruling
     * @param disputeId The ID of the dispute to execute
     */
    function executeRuling(uint256 disputeId) external {
        Dispute storage dispute = disputes[disputeId];
        if (state(disputeId) != DisputeState.Solved) revert DISPUTE_NOT_SOLVED();
        if (dispute.executed) revert DISPUTE_ALREADY_EXECUTED();

        uint256 winningChoice = _determineWinningChoice(disputeId);

        // Convert winning choice to Party enum
        IArbitrable.Party ruling = _convertChoiceToParty(winningChoice);

        dispute.rounds[dispute.currentRound].ruling = ruling;
        dispute.executed = true;

        // Call the rule function on the arbitrable contract
        arbitrable.rule(disputeId, uint256(ruling));

        emit DisputeExecuted(disputeId, ruling);
    }

    /**
     * @notice Determines the winning choice based on the votes.
     * @param _disputeID The ID of the dispute.
     * @return The choice with the highest votes.
     */
    function _determineWinningChoice(uint256 _disputeID) internal view returns (uint256) {
        Dispute storage dispute = disputes[_disputeID];
        uint256 winningChoice = 0;
        uint256 highestVotes = 0;
        uint256 round = dispute.currentRound;

        for (uint256 i = 1; i <= dispute.choices; i++) {
            if (dispute.rounds[round].choiceVotes[i] > highestVotes) {
                highestVotes = dispute.rounds[round].choiceVotes[i];
                winningChoice = i;
            }
        }

        return winningChoice;
    }

    /**
     * @notice Converts a choice number to the corresponding Party enum.
     * @param _choice The choice number.
     * @return The corresponding Party.
     */
    function _convertChoiceToParty(uint256 _choice) internal pure returns (IArbitrable.Party) {
        if (_choice == 1) {
            return IArbitrable.Party.Requester;
        } else if (_choice == 2) {
            return IArbitrable.Party.Challenger;
        } else {
            return IArbitrable.Party.None;
        }
    }

    /**
     * @notice Owner function for setting the voting delay
     * @param newVotingDelay new voting delay, in blocks
     */
    function _setVotingDelay(uint256 newVotingDelay) external onlyOwner {
        if (newVotingDelay < MIN_VOTING_DELAY || newVotingDelay > MAX_VOTING_DELAY) revert INVALID_VOTING_DELAY();
        uint256 oldVotingDelay = votingDelay;
        votingDelay = newVotingDelay;

        emit VotingDelaySet(oldVotingDelay, votingDelay);
    }

    /**
     * @notice Owner function for setting the quorum votes basis points
     * @dev newQuorumVotesBPS must be greater than the hardcoded min
     * @param newQuorumVotesBPS new dispute threshold
     */
    function _setQuorumVotesBPS(uint256 newQuorumVotesBPS) external onlyOwner {
        if (newQuorumVotesBPS < MIN_QUORUM_VOTES_BPS || newQuorumVotesBPS > MAX_QUORUM_VOTES_BPS)
            revert INVALID_QUORUM_VOTES_BPS();
        uint256 oldQuorumVotesBPS = quorumVotesBPS;
        quorumVotesBPS = newQuorumVotesBPS;

        emit QuorumVotesBPSSet(oldQuorumVotesBPS, quorumVotesBPS);
    }

    /**
     * @notice Owner function for setting the voting period
     * @param newVotingPeriod new voting period, in blocks
     */
    function _setVotingPeriod(uint256 newVotingPeriod) external onlyOwner {
        if (newVotingPeriod < MIN_VOTING_PERIOD || newVotingPeriod > MAX_VOTING_PERIOD) revert INVALID_VOTING_PERIOD();

        uint256 oldVotingPeriod = votingPeriod;
        votingPeriod = newVotingPeriod;

        emit VotingPeriodSet(oldVotingPeriod, votingPeriod);
    }

    function bps2Uint(uint256 bps, uint256 number) internal pure returns (uint256) {
        return (number * bps) / 10000;
    }

    function appealPeriod(uint256 _disputeID) external view override returns (uint256 start, uint256 end) {
        uint256 round = disputes[_disputeID].currentRound;
        return (
            disputes[_disputeID].rounds[round].revealPeriodEndTime,
            disputes[_disputeID].rounds[round].appealPeriodEndTime
        );
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
     * @notice Current quorum votes using Voting Token Total Supply
     */
    function quorumVotes() public view returns (uint256) {
        return bps2Uint(quorumVotesBPS, votingToken.totalSupply());
    }

    /**
     * @notice Returns the cost of arbitration
     * @return cost The cost of arbitration
     */
    function arbitrationCost(bytes calldata) external view override returns (uint256 cost) {
        return _arbitrationCost;
    }

    /**
     * @notice Returns the cost of appealing a dispute
     * @param disputeID The ID of the dispute
     * @return cost The cost of the appeal
     */
    function appealCost(uint256 disputeID, bytes calldata) external view returns (uint256 cost) {
        return _calculateAppealCost(disputes[disputeID].currentRound + 1);
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param _newImpl The new implementation address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
