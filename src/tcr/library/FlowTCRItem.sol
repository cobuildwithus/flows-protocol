// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { FlowTypes } from "../../storage/FlowStorageV1.sol";
import { IFlow } from "../../interfaces/IFlow.sol";
import { FlowRecipients } from "../../library/FlowRecipients.sol";

library FlowTCRItem {
    /**
     * @dev Verifies the data of an item before it's added to the registry.
     * @param _item The data describing the item to be added.
     * @param _requiredRecipientType The required recipient type for the TCR.
     * @return valid True if the item data is valid, false otherwise.
     */
    function verifyItemData(
        bytes calldata _item,
        FlowTypes.RecipientType _requiredRecipientType
    ) public returns (bool valid) {
        (
            address recipient,
            FlowTypes.RecipientMetadata memory metadata,
            FlowTypes.RecipientType recipientType
        ) = decodeItemData(_item);

        // Check if recipient is a valid address
        if (recipient == address(0)) {
            return false;
        }

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
        returns (address recipient, FlowTypes.RecipientMetadata memory metadata, FlowTypes.RecipientType recipientType)
    {
        return abi.decode(_item, (address, FlowTypes.RecipientMetadata, FlowTypes.RecipientType));
    }
}
