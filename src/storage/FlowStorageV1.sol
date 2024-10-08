// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { IFlow } from "../interfaces/IFlow.sol";
import { IERC721Checkpointable } from "../interfaces/IERC721Checkpointable.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import { PoolConfig } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface FlowTypes {
    // Struct to hold the recipientId and their corresponding BPS for a vote
    struct VoteAllocation {
        bytes32 recipientId;
        uint32 bps;
        uint128 memberUnits;
    }

    // Enum to handle type of grant recipient, either address or flow contract
    // Helpful to set a flow rate if recipient is flow contract
    enum RecipientType {
        None,
        ExternalAccount,
        FlowContract
    }

    // Struct to hold metadata for the flow contract itself
    struct RecipientMetadata {
        string title;
        string description;
        string image;
        string tagline;
        string url;
    }

    // Struct to handle potential recipients
    struct FlowRecipient {
        // the account to stream funds to
        address recipient;
        // whether or not the recipient has been removed
        bool removed;
        // the type of recipient, either account or flow contract
        RecipientType recipientType;
        // the metadata of the recipient
        RecipientMetadata metadata;
    }

    struct Storage {
        /// The proportion of the total flow rate (minus rewards) that is allocated to the baseline salary pool in BPS
        uint32 baselinePoolFlowRatePercent;
        /// THe proportion of the total flow rate that is allocated to the rewards pool in BPS
        uint32 managerRewardPoolFlowRatePercent;
        /// The flow implementation
        address flowImpl;
        /// The parent flow contract (optional)
        address parent;
        /// The flow manager
        address manager;
        /// The manager reward pool
        address managerRewardPool;
        /// Counter for active recipients (not removed)
        uint256 activeRecipientCount;
        // Public field for the flow contract metadata
        RecipientMetadata metadata;
        /// The mapping of recipients
        mapping(bytes32 => FlowRecipient) recipients;
        /// The mapping of addresses to whether they are a recipient
        mapping(address => bool) recipientExists;
        /// The SuperToken used to pay out the grantees
        ISuperToken superToken;
        /// The Superfluid pool used to distribute the bonus salary in the SuperToken
        ISuperfluidPool bonusPool;
        // The Superfluid pool used to distribute the baseline salary in the SuperToken
        ISuperfluidPool baselinePool;
        /// The mapping of a tokenId to the member units assigned to each recipient they voted for
        mapping(uint256 => mapping(address => uint256)) tokenIdToRecipientMemberUnits;
        // The weight of the 721 voting token
        uint256 tokenVoteWeight;
        // The mapping of a token to a list of votes allocations (recipient, BPS)
        mapping(uint256 => VoteAllocation[]) votes;
        // The mapping of a token to the address that voted with it
        mapping(uint256 => address) voters;
    }
}

/// @notice Flow Storage V1
/// @author rocketman
/// @notice The Flow storage contract
contract FlowStorageV1 is FlowTypes {
    /// @dev Warning - don't update the slot / position of these variables in the FlowStorageV1 contract
    /// without also changing the libraries that access them
    Storage public fs;

    /// @notice constant to scale uints into percentages (1e6 == 100%)
    /// @dev Heed warning above
    uint32 public constant PERCENTAGE_SCALE = 1e6;

    /// The member units to assign to each recipient of the baseline salary pool
    /// @dev Heed warning above
    uint128 public constant BASELINE_MEMBER_UNITS = 1e5;

    /// The enumerable list of child flow contracts
    /// @dev Heed warning above
    EnumerableSet.AddressSet internal _childFlows;
}
