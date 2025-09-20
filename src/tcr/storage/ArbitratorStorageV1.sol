// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IArbitrator } from "../interfaces/IArbitrator.sol";
import { IArbitrable } from "../interfaces/IArbitrable.sol";
import { ERC20VotesMintable } from "../../base/erc20/ERC20VotesMintable.sol";

/**
 * @title ArbitratorStorageV1
 * @notice Storage contract for the Arbitrator implementation
 */
contract ArbitratorStorageV1 {
    /** @notice The minimum setable voting period */
    // TODO update after testing
    uint256 public constant MIN_VOTING_PERIOD = 1; // 24 hours

    /** @notice The max setable voting period */
    uint256 public constant MAX_VOTING_PERIOD = 1_209_600; // 2 weeks

    /** @notice The min setable voting delay */
    uint256 public constant MIN_VOTING_DELAY = 1;

    /** @notice The max setable voting delay */
    uint256 public constant MAX_VOTING_DELAY = 604_800; // 1 week

    /** @notice The minimum setable reveal period */
    // TODO update after testing
    uint256 public constant MIN_REVEAL_PERIOD = 1; // 24 hours

    /** @notice The maximum setable reveal period */
    uint256 public constant MAX_REVEAL_PERIOD = 604_800; // 7 days

    /** @notice The minimum setable arbitration cost */
    uint256 public constant MIN_ARBITRATION_COST = 1e18 / 10_000; // 1 ten-thousandth of a token

    /** @notice The maximum setable arbitration cost */
    uint256 public constant MAX_ARBITRATION_COST = 1e18 * 1_000_000; // 1 million tokens

    /** @notice ERC20 token used for voting */
    ERC20VotesMintable public votingToken;

    /** @notice The arbitrable contract associated with this arbitrator */
    IArbitrable public arbitrable;

    /** @notice The number of seconds between the vote start and the vote end */
    uint256 public _votingPeriod;

    /** @notice The number of seconds between the proposal creation and the vote start */
    uint256 public _votingDelay;

    /** @notice The number of seconds for the reveal period after voting ends */
    uint256 public _revealPeriod;

    /** @notice The total number of disputes created */
    uint256 public disputeCount;

    /** @notice The cost of arbitration */
    uint256 public _arbitrationCost;

    /** @notice Ballot receipt record for a voter */
    struct Receipt {
        /** @notice Whether or not a vote has been cast */
        bool hasCommitted;
        /** @notice Whether or not a vote has been revealed */
        bool hasRevealed;
        /** @notice The secret hash of the voter's choice, reason (optional) and salt (tightly packed in this order) */
        bytes32 commitHash;
        /** @notice The choice of the voter. Invalid unless the vote has been revealed */
        uint256 choice;
        /** @notice The number of votes the voter had, which were cast */
        uint256 votes;
    }

    /** @notice Possible states that a dispute may be in */
    enum DisputeState {
        Pending, // Dispute is pending and not yet active for voting
        Active, // Dispute is active and open for voting
        Reveal, // Voting has ended, and votes can be revealed
        Solved // Dispute has been solved but not yet executed
    }

    /** @notice Struct containing dispute data */
    struct Dispute {
        /** @notice Unique identifier for the dispute */
        uint256 id;
        /** @notice Address of the arbitrable contract that created this dispute */
        address arbitrable;
        /** @notice Whether the dispute has been executed */
        bool executed;
        /** @notice Mapping of round numbers to VotingRound structs */
        mapping(uint256 => VotingRound) rounds;
        /** @notice The current round number of the dispute */
        uint256 currentRound;
        /** @notice The number of choices available for voting */
        uint256 choices;
        /** @notice The winning choice in the dispute */
        uint256 winningChoice;
    }

    struct VotingRound {
        /** @notice The cost paid by the arbitrable contract for this voting round. */
        uint256 cost;
        /** @notice Timestamp when voting commit period starts */
        uint256 votingStartTime;
        /** @notice Timestamp when voting commit period ends */
        uint256 votingEndTime;
        /** @notice Timestamp when the reveal period starts */
        uint256 revealPeriodStartTime;
        /** @notice Timestamp when the reveal period ends */
        uint256 revealPeriodEndTime;
        /** @notice Total number of votes cast */
        uint256 votes;
        /** @notice The winning choice in the dispute */
        IArbitrable.Party ruling;
        /** @notice The votes for each choice */
        mapping(uint256 => uint256) choiceVotes;
        /** @notice Additional data related to the dispute */
        bytes extraData;
        /** @notice Block number when the dispute was created */
        uint256 creationBlock;
        /** @notice Total supply of voting tokens at dispute creation */
        uint256 totalSupply;
        /** @notice Mapping of voter addresses to their voting receipts */
        mapping(address => Receipt) receipts;
        /** @notice Tracks whether a voter has claimed their reward */
        mapping(address => bool) rewardsClaimed;
    }

    /** @notice Mapping of dispute IDs to Dispute structs */
    mapping(uint256 => Dispute) public disputes;
}
