// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FlowTypes } from "../storage/FlowStorage.sol";
import { IFlow } from "../interfaces/IFlow.sol";
import { IAllocationStrategy } from "../interfaces/IAllocationStrategy.sol";

import { PoolConfig, SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

library FlowInitialization {
    using SuperTokenV1Library for ISuperToken;

    /**
     * @notice Checks the initialization parameters for the Flow contract
     * @param fs The storage of the Flow contract
     * @param _initialOwner The address of the initial owner
     * @param _flowImpl The address of the flow implementation
     * @param _manager The address of the flow manager
     * @param _superToken The address of the SuperToken to be used for the pool
     * @param _managerRewardPool The address of the manager reward pool (optional)
     * @param _parent The address of the parent flow contract (optional)
     * @param _flowAddress The address of the flow contract
     * @param _flowParams The parameters for the flow contract
     * @param _metadata The metadata for the flow contract
     * @param _strategies The allocation strategies to use.
     */
    function checkAndSetInitializationParams(
        FlowTypes.Storage storage fs,
        address _initialOwner,
        address _flowImpl,
        address _manager,
        address _superToken,
        address _managerRewardPool,
        address _parent,
        address _flowAddress,
        IFlow.FlowParams memory _flowParams,
        FlowTypes.RecipientMetadata memory _metadata,
        uint256 percentageScale,
        IAllocationStrategy[] calldata _strategies
    ) public {
        if (_initialOwner == address(0)) revert IFlow.ADDRESS_ZERO();
        if (_flowImpl == address(0)) revert IFlow.ADDRESS_ZERO();
        if (_manager == address(0)) revert IFlow.ADDRESS_ZERO();
        if (_superToken == address(0)) revert IFlow.ADDRESS_ZERO();
        if (bytes(_metadata.title).length == 0) revert IFlow.INVALID_METADATA();
        if (bytes(_metadata.description).length == 0) revert IFlow.INVALID_METADATA();
        if (bytes(_metadata.image).length == 0) revert IFlow.INVALID_METADATA();
        if (_flowParams.baselinePoolFlowRatePercent > percentageScale) revert IFlow.INVALID_RATE_PERCENT();
        if (_flowParams.managerRewardPoolFlowRatePercent > percentageScale) revert IFlow.INVALID_RATE_PERCENT();
        if (_strategies.length == 0) revert IFlow.INVALID_STRATEGIES();
        for (uint256 i = 0; i < _strategies.length; i++) {
            if (address(_strategies[i]) == address(0)) revert IFlow.ADDRESS_ZERO();

            // Check for duplicate strategies
            for (uint256 j = i + 1; j < _strategies.length; j++) {
                if (address(_strategies[i]) == address(_strategies[j])) {
                    revert IFlow.INVALID_STRATEGIES();
                }
            }
        }

        // Set the voting power info
        fs.baselinePoolFlowRatePercent = _flowParams.baselinePoolFlowRatePercent;
        fs.managerRewardPoolFlowRatePercent = _flowParams.managerRewardPoolFlowRatePercent;
        fs.flowImpl = _flowImpl;
        fs.manager = _manager;
        fs.parent = _parent;
        fs.managerRewardPool = _managerRewardPool;
        fs.strategies = _strategies;

        PoolConfig memory poolConfig = PoolConfig({
            transferabilityForUnitsOwner: false,
            distributionFromAnyAddress: true
        });

        fs.superToken = ISuperToken(_superToken);
        fs.bonusPool = fs.superToken.createPool(_flowAddress, poolConfig);
        fs.baselinePool = fs.superToken.createPool(_flowAddress, poolConfig);

        fs.defaultBufferMultiplier = 3;
        fs.outflowCapPct = 999e3; // 99.9% on 1e6

        // Set the metadata
        fs.metadata = _metadata;
    }
}
