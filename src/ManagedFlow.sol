// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { Flow } from "./Flow.sol";
import { IMangedFlow } from "./interfaces/IFlow.sol";
import { FlowVotes } from "./library/FlowVotes.sol";
import { FlowRates } from "./library/FlowRates.sol";
import { IChainalysisSanctionsList } from "./interfaces/external/chainalysis/IChainalysisSanctionsList.sol";

contract ManagedFlow is IMangedFlow, Flow {
    using FlowVotes for Storage;
    using FlowRates for Storage;

    // The address of the allocator - the EOA or contract that will allocate the flow
    address public allocator;

    // The virtual weight used for sub-BPS resolution in allocation calculations
    uint256 public constant virtualWeight = 1e36;

    // Errors
    error NOT_ALLOCATOR();

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
    }

    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function is virtual to allow for different deployment strategies in derived contracts
     * @param metadata The recipient's metadata like title, description, etc.
     * @param flowManager The address of the flow manager for the new contract
     * @param managerRewardPool The address of the manager reward pool for the new contract
     * @return recipient address The address of the newly created Flow contract
     */
    function _deployFlowRecipient(
        RecipientMetadata calldata metadata,
        address flowManager,
        address managerRewardPool
    ) internal override returns (address recipient) {
        revert("ManagedFlow: cannot currently deploy a new flow recipient");
    }
}
