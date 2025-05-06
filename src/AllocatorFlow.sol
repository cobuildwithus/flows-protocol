// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { Flow } from "./Flow.sol";
import { IAllocatorFlow } from "./interfaces/IFlow.sol";
import { FlowVotes } from "./library/FlowVotes.sol";
import { FlowPools } from "./library/FlowPools.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IChainalysisSanctionsList } from "./interfaces/external/chainalysis/IChainalysisSanctionsList.sol";

contract AllocatorFlow is IAllocatorFlow, Flow {
    using FlowVotes for Storage;
    using FlowPools for Storage;
    using EnumerableSet for EnumerableSet.AddressSet;

    // The address of the allocator - the EOA or contract that will allocate the flow
    address public allocator;

    // The virtual weight used for sub-BPS resolution in allocation calculations
    uint256 public constant virtualWeight = 1e21;

    EnumerableSet.AddressSet private _manualRecipients; // NEW storage var

    modifier onlyAllocator() {
        if (msg.sender != allocator) revert NOT_ALLOCATOR();
        _;
    }

    constructor() payable initializer {}

    function initialize(
        address _initialOwner,
        address _allocator,
        address _superToken,
        address _flowImpl,
        address _manager,
        address _managerRewardPool,
        address _parent,
        FlowParams calldata _flowParams,
        RecipientMetadata calldata _metadata,
        IChainalysisSanctionsList _sanctionsOracle
    ) public initializer {
        if (_allocator == address(0)) revert ADDRESS_ZERO();
        allocator = _allocator;

        emit AllocatorChanged(_allocator);

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

        // Since the flow is managed, it is entirely controlled by the allocator
        // No need to split the flow rate evenly, make it entirely bonus pool
        _setBaselineFlowRatePercent(0);
        _setBonusPoolQuorum(0);
    }

    /**
     * @notice Changes the allocator address
     * @dev Only callable by the owner
     * @param _newAllocator The address of the new allocator
     */
    function changeAllocator(address _newAllocator) external onlyOwner {
        if (_newAllocator == address(0)) revert ADDRESS_ZERO();

        allocator = _newAllocator;

        emit AllocatorChanged(_newAllocator);
    }

    /**
     * @dev Allows the allocator to push an arbitrary BPS split.
     *      Baseline is 0 %, bonus is 100 % of the incoming flow.
     */
    function setManualAllocations(
        bytes32[] calldata recipientIds,
        uint32[] calldata bps // must sum to 1e6
    ) external onlyAllocator nonReentrant {
        // 1. validate inputs (re-use library)
        fs.validateAllocations(recipientIds, bps, PERCENTAGE_SCALE);

        // 2. zero previous manual units
        address[] memory old = _manualRecipients.values();
        for (uint256 i = 0; i < old.length; ++i) {
            fs.updateBonusMemberUnits(old[i], 0);
            _manualRecipients.remove(old[i]);
        }

        // 3. apply new split
        for (uint256 i = 0; i < recipientIds.length; ++i) {
            address r = fs.recipients[recipientIds[i]].recipient;
            uint128 units = uint128(
                FlowVotes._scaleAmountByPercentage(virtualWeight, bps[i], PERCENTAGE_SCALE) / 1e15 // same down-scaling factor
            );
            fs.updateBonusMemberUnits(r, units);
            _manualRecipients.add(r);
        }

        // 4. propagate
        _setChildrenAsNeedingUpdates(address(0));
        _setFlowRate(getTotalFlowRate());
    }

    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function is virtual to allow for different deployment strategies in derived contracts
     * @return recipient address The address of the newly created Flow contract
     */
    function _deployFlowRecipient(
        RecipientMetadata calldata,
        address,
        address
    ) internal override returns (address recipient) {
        revert("AllocatorFlow: cannot currently deploy a new flow recipient");
    }
}
