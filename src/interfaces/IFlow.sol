// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FlowTypes } from "../storage/FlowStorage.sol";
import { IManagedFlow } from "./IManagedFlow.sol";
import { IAllocationStrategy } from "./IAllocationStrategy.sol";
import { IChainalysisSanctionsList } from "./external/chainalysis/IChainalysisSanctionsList.sol";

/**
 * @title IFlowEvents
 * @dev This interface defines the events for the Flow contract.
 */
interface IFlowEvents {
    /**
     * @dev Emitted when a vote is cast for a grant application.
     * @param recipientId Id of the recipient of the grant.
     * @param strategy The strategy that is allocating.
     * @param allocationKey The allocation key.
     * @param memberUnits New member units as a result of the allocation.
     * @param bps Basis points of the allocation. Proportion of the allocation weight that is allocated to the recipient.
     * @param totalWeight Total weight of the allocation
     */
    event AllocationSet(
        bytes32 indexed recipientId,
        address indexed strategy,
        uint256 indexed allocationKey,
        uint256 memberUnits,
        uint256 bps,
        uint256 totalWeight
    );

    /**
     * @dev Emitted when the manager reward flow rate percentage is updated
     * @param oldManagerRewardFlowRatePercent The old manager reward flow rate percentage
     * @param newManagerRewardFlowRatePercent The new manager reward flow rate percentage
     */
    event ManagerRewardFlowRatePercentUpdated(
        uint32 oldManagerRewardFlowRatePercent,
        uint32 newManagerRewardFlowRatePercent
    );

    /// @notice Emitted when a new child flow recipient is created
    event FlowRecipientCreated(
        bytes32 indexed recipientId,
        address indexed recipient,
        address baselinePool,
        address bonusPool,
        uint32 managerRewardPoolFlowRatePercent,
        uint32 baselinePoolFlowRatePercent
    );

    /// @notice Emitted when the metadata is set
    event MetadataSet(FlowTypes.RecipientMetadata metadata);

    /// @notice Emitted when the flow is initialized
    event FlowInitialized(
        address indexed owner,
        address indexed superToken,
        address indexed flowImpl,
        address manager,
        address managerRewardPool,
        address parent,
        address baselinePool,
        address bonusPool,
        uint32 baselinePoolFlowRatePercent,
        uint32 managerRewardPoolFlowRatePercent,
        IAllocationStrategy[] strategies
    );

    /// @notice Emitted when the manager reward pool is updated
    event ManagerRewardPoolUpdated(address indexed oldManagerRewardPool, address indexed newManagerRewardPool);

    /// @notice Emitted when a new grants recipient is set
    event RecipientCreated(bytes32 indexed recipientId, FlowTypes.FlowRecipient recipient, address indexed approvedBy);

    /// @notice Emitted when a new flow implementation is set
    event FlowImplementationSet(address indexed flowImpl);

    /// @notice Emitted when a recipient is removed
    event RecipientRemoved(address indexed recipient, bytes32 indexed recipientId);

    /// @notice Emitted when the baseline flow rate percentage is updated
    event BaselineFlowRatePercentUpdated(uint32 oldBaselineFlowRatePercent, uint32 newBaselineFlowRatePercent);

    /// @notice Emitted when the manager is updated
    event ManagerUpdated(address indexed oldManager, address indexed newManager);

    /// @notice Emitted when the bonus pool quorum is updated
    event BonusPoolQuorumUpdated(uint32 oldBonusPoolQuorum, uint32 newBonusPoolQuorum);

    /// @notice Emitted when the sanctions oracle is set
    event SanctionsOracleSet(address indexed newSanctionsOracle);
}

/**
 * @title IERC20FlowEvents
 * @dev This interface defines the events for ERC20-related functionality in the Flow contract.
 */
interface IERC20FlowEvents {
    /// @dev Emitted when the ERC20 voting token is changed
    event ERC20VotingTokenChanged(address indexed erc20Token);
}

/**
 * @title IFlowERC721Events
 * @dev This interface defines the events for ERC721-related functionality in the Flow contract.
 */
interface ICustomFlowEvents {
    /// @dev Emitted when the ERC721 voting token is changed
    event ERC721VotingTokenChanged(address indexed erc721Token);
}

/**
 * @title IFlow
 * @dev This interface defines the methods for the Flow contract.
 */
interface IFlow is IFlowEvents, IManagedFlow {
    ///                                                          ///
    ///                           ERRORS                         ///
    ///                                                          ///

    /// @dev Reverts if the provided address is not a valid child flow
    error NOT_A_VALID_CHILD_FLOW();

    /// @dev Reverts if the lengths of the provided arrays do not match.
    error ARRAY_LENGTH_MISMATCH();

    /// @dev Reverts if unit updates fail
    error UNITS_UPDATE_FAILED();

    /// @dev Reverts if the recipient is not found
    error RECIPIENT_NOT_FOUND();

    /// @dev Reverts if the recipient already exists
    error RECIPIENT_ALREADY_EXISTS();

    /// @dev Reverts if the baseline pool flow rate percent is invalid
    error INVALID_RATE_PERCENT();

    /// @dev Reverts if the flow rate is negative
    error FLOW_RATE_NEGATIVE();

    /// @dev Reverts if the flow rate is too high
    error FLOW_RATE_TOO_HIGH();

    /// @dev Reverts if the recipient is not approved.
    error NOT_APPROVED_RECIPIENT();

    /// @dev Reverts if the token vote weight is invalid (i.e., 0).
    error INVALID_VOTE_WEIGHT();

    /// @dev Reverts if the voter's weight is below the minimum required vote weight.
    error WEIGHT_TOO_LOW();

    /// @dev Reverts if the caller is not the owner or the parent
    error NOT_OWNER_OR_PARENT();

    /// @dev Reverts if the baseline flow rate percentage is invalid
    error INVALID_PERCENTAGE();

    /// @dev Reverts if invalid recipientId is passed
    error INVALID_RECIPIENT_ID();

    /// @dev Reverts if the voting signature is invalid
    error INVALID_SIGNATURE();

    /// @dev Reverts if the function caller is not the manager.
    error NOT_MANAGER();

    /// @dev Reverts if voting allocation casts will overflow
    error OVERFLOW();

    /// @dev Reverts if the strategies are invalid
    error INVALID_STRATEGIES();

    /// @dev Reverts if the ERC721 voting token weight is invalid (i.e., 0).
    error INVALID_ERC721_VOTING_WEIGHT();

    /// @dev Reverts if the ERC20 voting token weight is invalid (i.e., 0).
    error INVALID_ERC20_VOTING_WEIGHT();

    /// @dev Reverts if the voting signature has expired
    error SIGNATURE_EXPIRED();

    /// @dev Reverts if address 0 is passed but not allowed
    error ADDRESS_ZERO();

    /// @dev Reverts if bps does not sum to 10000
    error INVALID_BPS_SUM();

    /// @dev Reverts if bps is greater than 10000
    error INVALID_BPS();

    /// @dev Reverts if metadata is invalid
    error INVALID_METADATA();

    /// @dev Reverts if sender is not owner or manager
    error NOT_OWNER_OR_MANAGER();

    /// @dev Reverts if sender is not manager
    error SENDER_NOT_MANAGER();

    /// @dev Reverts if recipient is already approved
    error RECIPIENT_ALREADY_REMOVED();

    /// @dev Reverts if msg.sender is not able to allocate with the strategy
    error NOT_ABLE_TO_ALLOCATE();

    /// @dev Array lengths of recipients & percentAllocations don't match (`recipientsLength` != `allocationsLength`)
    /// @param recipientsLength Length of recipients array
    /// @param allocationsLength Length of percentAllocations array
    error RECIPIENTS_ALLOCATIONS_MISMATCH(uint256 recipientsLength, uint256 allocationsLength);

    /// @dev Reverts if no recipients are specified
    error TOO_FEW_RECIPIENTS();

    /// @dev Reverts if voting allocation is not positive
    error ALLOCATION_MUST_BE_POSITIVE();

    /// @dev Reverts if pool connection fails
    error POOL_CONNECTION_FAILED();

    /// @dev Reverts if recipient is sanctioned
    error SANCTIONED_RECIPIENT();

    ///                                                          ///
    ///                         STRUCTS                          ///
    ///                                                          ///

    // Struct representing a voter and their weight for a specific grant application.
    struct Vote {
        address voterAddress;
        uint256 weight;
    }

    /**
     * @notice Structure to hold the parameters for initializing a Flow contract.
     * @param baselinePoolFlowRatePercent The proportion of the total flow rate that is allocated to the baseline salary pool in BPS
     * @param managerRewardPoolFlowRatePercent The proportion of the total flow rate that is allocated to the rewards pool in BPS
     * @param bonusPoolQuorumBps The quorum for the bonus pool in BPS
     */
    struct FlowParams {
        uint32 baselinePoolFlowRatePercent;
        uint32 managerRewardPoolFlowRatePercent;
        uint32 bonusPoolQuorumBps;
    }

    /**
     * @notice Sets the flow rate for the Superfluid pool
     * @param _flowRate The new flow rate to be set
     * @dev Only callable by the owner or parent of the contract
     */
    function setFlowRate(int96 _flowRate) external;

    /**
     * @notice Gets the flow rate for the Superfluid pool
     * @return The flow rate for the Superfluid pool
     */
    function getTotalFlowRate() external view returns (int96);

    /**
     * @notice Gets the actual flow rate for the Superfluid pool
     * @return The actual flow rate for the Superfluid pool
     */
    function getActualFlowRate() external view returns (int96);

    /**
     * @notice Sets the manager reward pool for the flow contract
     * @param _managerRewardPool The address of the manager reward pool
     * @dev Only callable by the owner
     */
    function setManagerRewardPool(address _managerRewardPool) external;
}

interface INounsFlow is IFlow {
    /// @dev Reverts if the proof timestamp is too old
    error PAST_PROOF();

    /**
     * @notice Initializes an NounsFlow contract
     * @param initialOwner The address of the initial owner
     * @param verifier The address of the NounsVerifier contract
     * @param superToken The address of the SuperToken to be used for the pool
     * @param flowImpl The address of the flow implementation contract
     * @param manager The address of the flow manager
     * @param managerRewardPool The address of the manager reward pool
     * @param parent The address of the parent flow contract (optional)
     * @param flowParams The parameters for the flow contract
     * @param metadata The metadata for the flow contract
     * @param sanctionsOracle The address of the sanctions oracle
     */
    function initialize(
        address initialOwner,
        address verifier,
        address superToken,
        address flowImpl,
        address manager,
        address managerRewardPool,
        address parent,
        FlowParams memory flowParams,
        FlowTypes.RecipientMetadata memory metadata,
        IChainalysisSanctionsList sanctionsOracle
    ) external;
}

interface ICustomFlow is IFlow {
    /**
     * @notice Initializes an CustomFlow contract
     * @param initialOwner The address of the initial owner
     * @param superToken The address of the SuperToken to be used for the pool
     * @param flowImpl The address of the flow implementation contract
     * @param manager The address of the flow manager
     * @param managerRewardPool The address of the manager reward pool
     * @param parent The address of the parent flow contract (optional)
     * @param flowParams The parameters for the flow contract
     * @param metadata The metadata for the flow contract
     * @param sanctionsOracle The address of the sanctions oracle
     * @param strategies The allocation strategies to use.
     */
    function initialize(
        address initialOwner,
        address superToken,
        address flowImpl,
        address manager,
        address managerRewardPool,
        address parent,
        FlowParams memory flowParams,
        FlowTypes.RecipientMetadata memory metadata,
        IChainalysisSanctionsList sanctionsOracle,
        IAllocationStrategy[] calldata strategies
    ) external;
}
