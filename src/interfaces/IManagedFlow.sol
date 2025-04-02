// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FlowTypes } from "../storage/FlowStorage.sol";
import { ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

interface IManagedFlow {
    /**
     * @notice Adds an address to the list of approved recipients
     * @param newRecipientId The ID of the recipient
     * @param recipient The address to be added as an approved recipient
     * @param metadata The metadata of the recipient
     * @return recipientId The ID of the recipient
     * @return recipientAddress The address of the Flow recipient
     */
    function addRecipient(
        bytes32 newRecipientId,
        address recipient,
        FlowTypes.RecipientMetadata memory metadata
    ) external returns (bytes32 recipientId, address recipientAddress);

    /**
     * @notice Adds a new Flow contract as a recipient
     * @param newRecipientId The ID of the recipient
     * @param metadata The metadata of the recipient
     * @param flowManager The address of the flow manager for the new contract
     * @param managerRewardPool The address of the manager reward pool for the new contract
     * @return recipientId The ID of the recipient
     * @return recipientAddress The address of the newly created flow contract
     */
    function addFlowRecipient(
        bytes32 newRecipientId,
        FlowTypes.RecipientMetadata memory metadata,
        address flowManager,
        address managerRewardPool
    ) external returns (bytes32 recipientId, address recipientAddress);

    /**
     * @notice Removes a recipient for receiving funds
     * @param recipientId The ID of the recipient to be removed
     */
    function removeRecipient(bytes32 recipientId) external;

    /**
     * @notice Resets the flow rate for the Flow contract to the cached value
     */
    function resetFlowRate() external;

    /**
     * @notice Sets a new manager for the Flow contract
     * @param _newManager The address of the new manager
     */
    function setManager(address _newManager) external;

    /**
     * @notice Sets a new manager reward pool for the Flow contract
     * @param _newManagerRewardPool The address of the new manager reward pool
     */
    function setManagerRewardPool(address _newManagerRewardPool) external;

    /**
     * @notice Returns the SuperToken address
     * @return The address of the SuperToken
     */
    function getSuperToken() external view returns (address);

    /**
     * @notice Returns the flow baseline pool address
     * @return The address of the flow baseline pool
     */
    function baselinePool() external view returns (ISuperfluidPool);

    /**
     * @notice Returns the flow manager reward pool address
     * @return The address of the flow manager reward pool
     */
    function managerRewardPool() external view returns (address);

    /**
     * @notice Returns the flow parent address
     * @return The address of the flow parent
     */
    function parent() external view returns (address);

    /**
     * @notice Returns the flow manager reward pool flow rate percent
     * @return The flow rate percent of the flow manager reward pool
     */
    function managerRewardPoolFlowRatePercent() external view returns (uint32);

    /**
     * @notice Returns the flow baseline pool flow rate percent
     * @return The flow rate percent of the flow baseline pool
     */
    function baselinePoolFlowRatePercent() external view returns (uint32);

    /**
     * @notice Returns the flow bonus pool address
     * @return The address of the flow bonus pool
     */
    function bonusPool() external view returns (ISuperfluidPool);

    /**
     * @notice Checks if a recipient exists in the Flow contract
     * @param recipient The address of the recipient to check
     * @return exists True if the recipient exists, false otherwise
     */
    function recipientExists(address recipient) external view returns (bool exists);
}
