// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FlowTypes } from "../storage/FlowStorage.sol";
import { IFlow } from "../interfaces/IFlow.sol";
import { Flow } from "../Flow.sol";

import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";

library FlowPools {
    using SuperTokenV1Library for ISuperToken;

    /**
     * @notice Connects a new Flow contract to both pools and initializes its member units
     * @param fs The storage of the Flow contract
     * @param recipient The address of the new Flow contract
     * @param baselineMemberUnits The number of units to be assigned to the baseline pool
     * @param defaultBonusMemberUnits The number of units to be assigned to the bonus pool
     */
    function connectAndInitializeFlowRecipient(
        FlowTypes.Storage storage fs,
        address recipient,
        uint128 baselineMemberUnits,
        uint128 defaultBonusMemberUnits
    ) public {
        // Connect the new child contract to both pools
        Flow(recipient).connectPool(fs.bonusPool);
        Flow(recipient).connectPool(fs.baselinePool);

        // Initialize member units
        updateBaselineMemberUnits(fs, recipient, baselineMemberUnits);
        updateBonusMemberUnits(fs, recipient, defaultBonusMemberUnits);
    }

    /**
     * @notice Sets the flow to the manager reward pool
     * @param fs The storage of the Flow contract
     * @param self The address of the Flow contract
     * @param _currentManagerRewardFlowRate The current flow rate to the manager reward pool
     * @param _newManagerRewardFlowRate The new flow rate to the manager reward pool
     */
    function setFlowToManagerRewardPool(
        FlowTypes.Storage storage fs,
        address self,
        int96 _currentManagerRewardFlowRate,
        int96 _newManagerRewardFlowRate
    ) public {
        if (_newManagerRewardFlowRate > 0) {
            // if flow to reward pool is 0, create a flow, otherwise update the flow
            if (_currentManagerRewardFlowRate == 0) {
                // todo need to check this - could it go to 0, then back to > 0 without needing to create a new flow?
                fs.superToken.createFlow(fs.managerRewardPool, _newManagerRewardFlowRate);
            } else {
                fs.superToken.updateFlow(fs.managerRewardPool, _newManagerRewardFlowRate);
            }
        } else if (_currentManagerRewardFlowRate > 0 && _newManagerRewardFlowRate == 0) {
            // only delete if the flow rate is going to 0 and reward pool flow rate is currently > 0
            fs.superToken.deleteFlow(self, fs.managerRewardPool);
        }
    }

    /**
     * @notice Resets the flow distribution after removing a recipient
     * @dev This function should be called after removing a recipient to ensure proper flow rate distribution
     * @param fs The storage of the Flow contract
     * @param recipientAddress The address of the removed recipient
     */
    function removeFromPools(FlowTypes.Storage storage fs, address recipientAddress) public {
        updateBonusMemberUnits(fs, recipientAddress, 0);
        updateBaselineMemberUnits(fs, recipientAddress, 0);
    }

    /**
     * @notice Updates the member units in the Superfluid pool
     * @param fs The storage of the Flow contract
     * @param member The address of the member whose units are being updated
     * @param units The new number of units to be assigned to the member
     * @dev Reverts with UNITS_UPDATE_FAILED if the update fails
     */
    function updateBonusMemberUnits(FlowTypes.Storage storage fs, address member, uint128 units) public {
        bool success = ISuperfluidPool(fs.bonusPool).updateMemberUnits(member, units);

        if (!success) revert IFlow.UNITS_UPDATE_FAILED();
    }

    /**
     * @notice Updates the member units for the baseline Superfluid pool
     * @param fs The storage of the Flow contract
     * @param member The address of the member whose units are being updated
     * @param units The new number of units to be assigned to the member
     * @dev Reverts with UNITS_UPDATE_FAILED if the update fails
     */
    function updateBaselineMemberUnits(FlowTypes.Storage storage fs, address member, uint128 units) public {
        bool success = ISuperfluidPool(fs.baselinePool).updateMemberUnits(member, units);

        if (!success) revert IFlow.UNITS_UPDATE_FAILED();
    }

    /**
     * @notice Ensures both pools have at least 1 unit to prevent flow rate from resetting to 0
     * @param fs The storage of the Flow contract
     * @param self The address of the Flow contract
     */
    function ensureMinimumPoolUnits(FlowTypes.Storage storage fs, address self) public {
        if (fs.bonusPool.getTotalUnits() == 0) {
            updateBonusMemberUnits(fs, self, 1);
        }
        if (fs.baselinePool.getTotalUnits() == 0) {
            updateBaselineMemberUnits(fs, self, 1);
        }
    }

    /**
     * @notice Distributes flow rates to both bonus and baseline pools
     * @param fs The storage of the Flow contract
     * @param self The address of the Flow contract
     * @param bonusFlowRate The flow rate for the bonus pool
     * @param baselineFlowRate The flow rate for the baseline pool
     */
    function distributeFlowToPools(
        FlowTypes.Storage storage fs,
        address self,
        int96 bonusFlowRate,
        int96 baselineFlowRate
    ) public {
        fs.superToken.distributeFlow(self, fs.bonusPool, bonusFlowRate);
        fs.superToken.distributeFlow(self, fs.baselinePool, baselineFlowRate);
    }
}
