// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { Flow } from "../Flow.sol";
import { ICustomFlow } from "../interfaces/IFlow.sol";
import { FlowAllocations } from "../library/FlowAllocations.sol";
import { CustomFlowLibrary } from "../library/CustomFlowLibrary.sol";
import { IChainalysisSanctionsList } from "../interfaces/external/chainalysis/IChainalysisSanctionsList.sol";
import { IAllocationStrategy } from "../interfaces/IAllocationStrategy.sol";

contract CustomFlow is ICustomFlow, Flow {
    using FlowAllocations for Storage;
    using CustomFlowLibrary for Storage;

    constructor() payable {
        _disableInitializers();
    }

    function initialize(
        address _initialOwner,
        address _superToken,
        address _flowImpl,
        address _manager,
        address _managerRewardPool,
        address _parent,
        address _connectPoolAdmin,
        FlowParams calldata _flowParams,
        RecipientMetadata calldata _metadata,
        IChainalysisSanctionsList _sanctionsOracle,
        IAllocationStrategy[] calldata _strategies
    ) public initializer {
        __Flow_init(
            _initialOwner,
            _superToken,
            _flowImpl,
            _manager,
            _managerRewardPool,
            _parent,
            _connectPoolAdmin,
            _flowParams,
            _metadata,
            _sanctionsOracle,
            _strategies
        );
    }

    /**
     * @notice Cast a vote for a set of grant addresses.
     * @param allocationData The allocation data to use. 2D array of bytes, where each inner array is the set of allocation data to be parsed for a given strategy.
     * @param recipientIds The recpientIds of the grant recipients.
     * @param percentAllocations The basis points of the allocation to be split with the recipients.
     */
    function allocate(
        bytes[][] calldata allocationData,
        bytes32[] calldata recipientIds,
        uint32[] calldata percentAllocations
    ) external nonReentrant {
        fs.validateAllocations(recipientIds, percentAllocations);

        if (allocationData.length != fs.strategies.length) revert ALLOCATION_LENGTH_MISMATCH();

        uint256 totalFlowsToUpdate = 0;
        bool shouldUpdateFlowRate = false;

        for (uint256 i = 0; i < fs.strategies.length; i++) {
            IAllocationStrategy strategy = fs.strategies[i];
            for (uint256 j = 0; j < allocationData[i].length; j++) {
                uint256 localKey = strategy.allocationKey(msg.sender, allocationData[i][j]);

                if (!strategy.canAllocate(localKey, msg.sender)) revert NOT_ABLE_TO_ALLOCATE();

                (uint256 flowsToUpdate, bool updateFlowRate) = _setAllocationForKey(
                    address(strategy),
                    localKey,
                    recipientIds,
                    percentAllocations,
                    msg.sender,
                    strategy.currentWeight(localKey)
                );
                totalFlowsToUpdate += flowsToUpdate;
                shouldUpdateFlowRate = shouldUpdateFlowRate || updateFlowRate;
            }
        }

        _afterAllocationSet(recipientIds, totalFlowsToUpdate, shouldUpdateFlowRate);
    }

    /**
     * @notice Cast a vote for a set of grant addresses, using commitment + witness.
     * @param allocationData Per-strategy opaque data used to derive allocation keys (same shape as before).
     * @param prevAllocationWitnesses A 2D array of ABI-encoded witnesses per key, same shape as allocationData.
     *        Each witness MUST be bytes-encoded as: abi.encode(uint256 prevWeight, bytes32[] prevRecipientIds, uint32[] prevBps).
     *        For the first call after upgrade (or a new key), you may pass empty bytes; the implementation
     *        will derive previous allocations from legacy storage if present, otherwise assume none.
     * @param recipientIds The new recipientIds for this allocation (applies to all keys in this call).
     * @param percentAllocations The new BPS per recipient (applies to all keys in this call).
     */
    function allocateWithWitness(
        bytes[][] calldata allocationData,
        bytes[][] calldata prevAllocationWitnesses,
        bytes32[] calldata recipientIds,
        uint32[] calldata percentAllocations
    ) external nonReentrant {
        fs.validateAllocations(recipientIds, percentAllocations);

        if (allocationData.length != fs.strategies.length) revert ALLOCATION_LENGTH_MISMATCH();
        if (prevAllocationWitnesses.length != allocationData.length) revert ALLOCATION_LENGTH_MISMATCH();

        uint256 totalFlowsToUpdate = 0;
        bool shouldUpdateFlowRate = false;

        for (uint256 i = 0; i < fs.strategies.length; ) {
            IAllocationStrategy strategy = fs.strategies[i];
            if (prevAllocationWitnesses[i].length != allocationData[i].length) revert ALLOCATION_LENGTH_MISMATCH();

            for (uint256 j = 0; j < allocationData[i].length; ) {
                uint256 localKey = strategy.allocationKey(msg.sender, allocationData[i][j]);
                if (!strategy.canAllocate(localKey, msg.sender)) revert NOT_ABLE_TO_ALLOCATE();

                // Decode per-key previous allocation witness (if any)
                bytes memory w = prevAllocationWitnesses[i][j];
                uint256 prevWeight;
                bytes32[] memory prevIds;
                uint32[] memory prevBps;
                if (w.length == 0) {
                    prevWeight = 0;
                    prevIds = new bytes32[](0);
                    prevBps = new uint32[](0);
                } else {
                    (prevWeight, prevIds, prevBps) = abi.decode(w, (uint256, bytes32[], uint32[]));
                }

                (uint256 flowsToUpdate, bool updateFlowRate) = _applyAllocationWithWitness(
                    address(strategy),
                    localKey,
                    prevIds,
                    prevBps,
                    prevWeight,
                    recipientIds,
                    percentAllocations
                );
                totalFlowsToUpdate += flowsToUpdate;
                if (updateFlowRate) shouldUpdateFlowRate = true;

                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }

        _afterAllocationSet(recipientIds, totalFlowsToUpdate, shouldUpdateFlowRate);
    }

    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function is virtual to allow for different deployment strategies in derived contracts
     * @param metadata The recipient's metadata like title, description, etc.
     * @param flowManager The address of the flow manager for the new contract
     * @param managerRewardPool The address of the manager reward pool for the new contract
     * @param strategies The allocation strategies to use.
     * @return recipient address The address of the newly created Flow contract
     */
    function _deployFlowRecipient(
        RecipientMetadata calldata metadata,
        address flowManager,
        address managerRewardPool,
        IAllocationStrategy[] calldata strategies
    ) internal override returns (address recipient) {
        recipient = fs.deployFlowRecipient(
            metadata,
            flowManager,
            managerRewardPool,
            owner(),
            address(this),
            strategies
        );
    }

    /**
     * @notice Function to calculate the total vote weight of all tokens used for voting
     * @dev This function can be overridden in derived contracts to implement custom logic
     * @return uint256 The total vote weight of all tokens used for voting
     */
    function totalAllocationWeight() public view override returns (uint256) {
        uint256 weight = 0;
        for (uint256 i = 0; i < fs.strategies.length; i++) {
            weight += fs.strategies[i].totalAllocationWeight();
        }
        return weight;
    }
}
