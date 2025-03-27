// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FlowTypes } from "../storage/FlowStorage.sol";
import { IFlow } from "../interfaces/IFlow.sol";

library FlowRecipients {
    /**
     * @notice Removes a recipient for receiving funds
     * @param fs The storage of the Flow contract
     * @param recipientId The ID of the recipient to be approved
     * @dev Only callable by the manager of the contract
     * @dev Emits a RecipientRemoved event if the recipient is successfully removed
     * @return address The address of the removed recipient
     */
    function removeRecipient(
        FlowTypes.Storage storage fs,
        bytes32 recipientId
    ) external returns (address, FlowTypes.RecipientType) {
        if (fs.recipients[recipientId].recipient == address(0)) revert IFlow.INVALID_RECIPIENT_ID();
        if (fs.recipients[recipientId].removed) revert IFlow.RECIPIENT_ALREADY_REMOVED();

        address recipientAddress = fs.recipients[recipientId].recipient;
        FlowTypes.RecipientType recipientType = fs.recipients[recipientId].recipientType;
        fs.recipientExists[recipientAddress] = false;

        fs.recipients[recipientId].removed = true;
        fs.activeRecipientCount--;

        return (recipientAddress, recipientType);
    }

    /**
     * @notice Adds an address to the list of approved recipients
     * @param fs The storage of the Flow contract
     * @param recipientId The ID of the recipient to be approved
     * @param recipient The address to be added as an approved recipient
     * @param metadata The metadata of the recipient
     * @return bytes32 The recipientId of the newly created recipient
     * @return address The address of the newly created recipient
     */
    function addRecipient(
        FlowTypes.Storage storage fs,
        bytes32 recipientId,
        address recipient,
        FlowTypes.RecipientMetadata memory metadata
    ) external returns (bytes32, address) {
        validateMetadata(metadata);

        if (recipient == address(0)) revert IFlow.ADDRESS_ZERO();
        if (fs.recipientExists[recipient]) revert IFlow.RECIPIENT_ALREADY_EXISTS();
        if (fs.recipients[recipientId].recipient != address(0)) revert IFlow.RECIPIENT_ALREADY_EXISTS();

        fs.recipientExists[recipient] = true;

        fs.recipients[recipientId] = FlowTypes.FlowRecipient({
            recipientType: FlowTypes.RecipientType.ExternalAccount,
            removed: false,
            recipient: recipient,
            metadata: metadata
        });

        fs.activeRecipientCount++;

        return (recipientId, recipient);
    }

    /**
     * @notice Adds an Flow address to the list of approved recipients
     * @param fs The storage of the Flow contract
     * @param recipientId The ID of the recipient to be approved
     * @param recipient The address to be added as an approved recipient
     * @param metadata The metadata of the recipient
     * @return bytes32 The recipientId of the newly created recipient
     */
    function addFlowRecipient(
        FlowTypes.Storage storage fs,
        bytes32 recipientId,
        address recipient,
        FlowTypes.RecipientMetadata memory metadata
    ) external returns (bytes32) {
        if (fs.recipientExists[recipient]) revert IFlow.RECIPIENT_ALREADY_EXISTS();
        if (fs.recipients[recipientId].recipient != address(0)) revert IFlow.RECIPIENT_ALREADY_EXISTS();

        fs.recipients[recipientId] = FlowTypes.FlowRecipient({
            recipientType: FlowTypes.RecipientType.FlowContract,
            removed: false,
            recipient: recipient,
            metadata: metadata
        });

        fs.recipientExists[recipient] = true;

        fs.activeRecipientCount++;

        return recipientId;
    }

    /**
     * @notice Modifier to validate the metadata for a recipient
     * @param metadata The metadata to validate
     */
    function validateMetadata(FlowTypes.RecipientMetadata memory metadata) public pure {
        if (bytes(metadata.title).length == 0) revert IFlow.INVALID_METADATA();
        if (bytes(metadata.description).length == 0) revert IFlow.INVALID_METADATA();
        if (bytes(metadata.image).length == 0) revert IFlow.INVALID_METADATA();
    }

    /**
     * @notice Modifier to validate the metadata for a recipient
     * @param metadata The metadata to validate
     * @param flowManager The address of the flow manager
     */
    function validateFlowRecipient(FlowTypes.RecipientMetadata memory metadata, address flowManager) public pure {
        validateMetadata(metadata);
        if (flowManager == address(0)) revert IFlow.ADDRESS_ZERO();
    }

    /**
     * @notice Gets the total amount received by a member across both baseline and bonus pools
     * @param fs The storage of the Flow contract
     * @param memberAddr The address of the member to check
     * @return uint256 The total amount received by the member
     */
    function getTotalAmountReceivedByMember(
        FlowTypes.Storage storage fs,
        address memberAddr
    ) external view returns (uint256) {
        return
            fs.bonusPool.getTotalAmountReceivedByMember(memberAddr) +
            fs.baselinePool.getTotalAmountReceivedByMember(memberAddr);
    }
}
