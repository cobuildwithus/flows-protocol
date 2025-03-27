// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FlowTypes } from "../../storage/FlowStorage.sol";
import { IManagedFlow } from "../../interfaces/IManagedFlow.sol";
import { FlowRecipients } from "../../library/FlowRecipients.sol";

library FlowTCRItems {
    /**
     * @dev Verifies the data of an item before it's added to the registry.
     * @param _item The data describing the item to be added.
     * @param _requiredRecipientType The required recipient type for the TCR.
     * @param _flowContract The Flow contract to check for recipient existence.
     * @return valid True if the item data is valid, false otherwise.
     */
    function verifyItemData(
        bytes calldata _item,
        FlowTypes.RecipientType _requiredRecipientType,
        IManagedFlow _flowContract
    ) public view returns (bool valid) {
        (
            address recipient,
            FlowTypes.RecipientMetadata memory metadata,
            FlowTypes.RecipientType recipientType
        ) = decodeItemData(_item);

        // Check if metadata is valid
        try FlowRecipients.validateMetadata(metadata) {
            // Metadata is valid
        } catch {
            return false;
        }

        // Check if recipientType is valid
        if (_requiredRecipientType != FlowTypes.RecipientType.None && recipientType != _requiredRecipientType) {
            return false;
        }

        if (
            recipientType != FlowTypes.RecipientType.ExternalAccount &&
            recipientType != FlowTypes.RecipientType.FlowContract
        ) {
            return false;
        }

        // Check if recipient is a valid address if passing external account
        if (recipientType == FlowTypes.RecipientType.ExternalAccount && recipient == address(0)) {
            return false;
        }
        // Check if recipient is the 0 address if passing flow contract - since flow contract is created when adding a flow recipient
        // it should be the 0 address
        if (recipientType == FlowTypes.RecipientType.FlowContract && recipient != address(0)) {
            return false;
        }

        // Check if recipient already exists in the Flow contract
        if (_flowContract.recipientExists(recipient)) {
            return false;
        }

        return true;
    }

    /**
     * @dev Decodes the item data.
     * @param _item The data describing the item.
     * @return recipient The address of the recipient.
     * @return metadata The metadata of the recipient.
     * @return recipientType The type of the recipient.
     */
    function decodeItemData(
        bytes memory _item
    )
        public
        pure
        returns (address recipient, FlowTypes.RecipientMetadata memory metadata, FlowTypes.RecipientType recipientType)
    {
        return abi.decode(_item, (address, FlowTypes.RecipientMetadata, FlowTypes.RecipientType));
    }
}
