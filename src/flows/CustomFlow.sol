// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { Flow } from "../Flow.sol";
import { ICustomFlow } from "../interfaces/IFlow.sol";
import { IRewardPool } from "../interfaces/IRewardPool.sol";
import { FlowVotes } from "../library/FlowVotes.sol";
import { FlowRates } from "../library/FlowRates.sol";
import { CustomFlowLibrary } from "../library/CustomFlowLibrary.sol";
import { IChainalysisSanctionsList } from "../interfaces/external/chainalysis/IChainalysisSanctionsList.sol";
import { IAllocationStrategy } from "../interfaces/IAllocationStrategy.sol";

contract CustomFlow is ICustomFlow, Flow {
    using FlowVotes for Storage;
    using FlowRates for Storage;
    using CustomFlowLibrary for Storage;

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
        IAllocationStrategy[] calldata _strategies
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
        fs.validateAllocations(recipientIds, percentAllocations, PERCENTAGE_SCALE);

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

        _afterVotesCast(recipientIds, totalFlowsToUpdate, shouldUpdateFlowRate);
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
            PERCENTAGE_SCALE,
            strategies
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
    function totalAllocationWeight() public view override returns (uint256) {
        uint256 totalAllocationWeight = 0;
        for (uint256 i = 0; i < fs.strategies.length; i++) {
            totalAllocationWeight += fs.strategies[i].totalAllocationWeight();
        }
        return totalAllocationWeight;
    }
}
