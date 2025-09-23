// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FlowTypes } from "../storage/FlowStorage.sol";
import { IFlow, IFlowEvents } from "../interfaces/IFlow.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { FlowPools } from "./FlowPools.sol";
import { FlowRates } from "./FlowRates.sol";
import { IChainalysisSanctionsList } from "../interfaces/external/chainalysis/IChainalysisSanctionsList.sol";

library FlowRecipients {
    using EnumerableSet for EnumerableSet.AddressSet;
    using FlowRates for FlowTypes.Storage;
    using FlowPools for FlowTypes.Storage;

    /**
     * @notice Removes a recipient for receiving funds
     * @param fs The storage of the Flow contract
     * @param _childFlows The set of child flows
     * @param _childFlowsToUpdateFlowRate The set of child flows to update flow rate
     * @param recipientId The ID of the recipient to be approved
     * @dev Only callable by the manager of the contract
     * @dev Emits a RecipientRemoved event if the recipient is successfully removed
     * @return address The address of the removed recipient
     */
    function removeRecipient(
        FlowTypes.Storage storage fs,
        EnumerableSet.AddressSet storage _childFlows,
        EnumerableSet.AddressSet storage _childFlowsToUpdateFlowRate,
        bytes32 recipientId
    ) public returns (address, FlowTypes.RecipientType) {
        if (fs.recipients[recipientId].recipient == address(0)) revert IFlow.INVALID_RECIPIENT_ID();
        if (fs.recipients[recipientId].removed) revert IFlow.RECIPIENT_ALREADY_REMOVED();

        address recipientAddress = fs.recipients[recipientId].recipient;
        FlowTypes.RecipientType recipientType = fs.recipients[recipientId].recipientType;
        fs.recipientExists[recipientAddress] = false;

        fs.recipients[recipientId].removed = true;
        fs.activeRecipientCount--;

        if (recipientType == FlowTypes.RecipientType.FlowContract) {
            _childFlows.remove(recipientAddress);
            _childFlowsToUpdateFlowRate.remove(recipientAddress);
        }

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
    ) public returns (bytes32, address) {
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
    ) public returns (bytes32) {
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

    /**
     * @notice Adds many EOA recipients in one transaction
     * @dev Emits RecipientCreated for each and kicks the worker queue once
     * @param fs Flow storage
     * @param _childFlows Set of child flows
     * @param _childFlowsToUpdateFlowRate Queue of child flows needing updates
     * @param flowAddress Address of the calling flow (parent) for worker ops
     * @param recipientIds Ids for the recipients
     * @param recipients EOA addresses
     * @param metadatas Metadata for each recipient
     * @param baselineUnits Units to grant in baseline pool per recipient
     * @param bonusUnits Units to grant in bonus pool per recipient
     * @return addedAddrs The addresses actually added
     */
    function bulkAddRecipients(
        FlowTypes.Storage storage fs,
        EnumerableSet.AddressSet storage _childFlows,
        EnumerableSet.AddressSet storage _childFlowsToUpdateFlowRate,
        address flowAddress,
        bytes32[] calldata recipientIds,
        address[] calldata recipients,
        FlowTypes.RecipientMetadata[] calldata metadatas,
        uint128 baselineUnits,
        uint128 bonusUnits
    ) public returns (address[] memory addedAddrs) {
        uint256 n = recipientIds.length;
        if (n == 0) revert IFlow.TOO_FEW_RECIPIENTS();
        if (recipients.length != n || metadatas.length != n) revert IFlow.ARRAY_LENGTH_MISMATCH();

        addedAddrs = new address[](n);

        // Phase 1 — add recipients and enforce sanctions
        for (uint256 i = 0; i < n; ) {
            (, address recipientAddr) = addRecipient(fs, recipientIds[i], recipients[i], metadatas[i]);

            IChainalysisSanctionsList sanctionsOracle_ = fs.sanctionsOracle;
            if (address(sanctionsOracle_) != address(0)) {
                if (sanctionsOracle_.isSanctioned(recipients[i])) revert IFlow.SANCTIONED_RECIPIENT();
            }

            emit IFlowEvents.RecipientCreated(recipientIds[i], fs.recipients[recipientIds[i]], msg.sender);
            addedAddrs[i] = recipientAddr;

            unchecked {
                ++i;
            }
        }

        // Phase 2 — snapshot surviving children once before unit changes
        fs.setChildrenAsNeedingUpdates(_childFlows, _childFlowsToUpdateFlowRate, address(0));

        // Phase 3 — grant baseline/bonus units per new recipient
        for (uint256 i = 0; i < n; ) {
            fs.updateBaselineMemberUnits(addedAddrs[i], baselineUnits);
            fs.updateBonusMemberUnits(addedAddrs[i], bonusUnits);
            unchecked {
                ++i;
            }
        }

        // Phase 4 — kick a few children in this tx
        fs.workOnChildFlowsToUpdate(_childFlowsToUpdateFlowRate, _childFlows, flowAddress, 10);
    }

    /**
     * @notice Removes many recipients in one transaction
     * @dev Emits RecipientRemoved for each, snapshots before zeroing units
     * @param fs Flow storage
     * @param _childFlows Set of child flows
     * @param _childFlowsToUpdateFlowRate Queue of child flows needing updates
     * @param recipientIds Ids to remove
     */
    function bulkRemoveRecipients(
        FlowTypes.Storage storage fs,
        EnumerableSet.AddressSet storage _childFlows,
        EnumerableSet.AddressSet storage _childFlowsToUpdateFlowRate,
        bytes32[] calldata recipientIds
    ) public {
        uint256 n = recipientIds.length;
        if (n == 0) revert IFlow.TOO_FEW_RECIPIENTS();

        address[] memory removedAddrs = new address[](n);
        FlowTypes.RecipientType[] memory removedTypes = new FlowTypes.RecipientType[](n);

        // Phase 1 — mark removed (no units changed yet)
        for (uint256 i = 0; i < n; ) {
            (address recipientAddr, FlowTypes.RecipientType rType) = removeRecipient(
                fs,
                _childFlows,
                _childFlowsToUpdateFlowRate,
                recipientIds[i]
            );
            removedAddrs[i] = recipientAddr;
            removedTypes[i] = rType;

            if (rType == FlowTypes.RecipientType.FlowContract) {
                fs.clearFlowRateSnapshot(recipientAddr);
            }

            unchecked {
                ++i;
            }
        }

        // Phase 2 — snapshot surviving children once before unit changes
        fs.setChildrenAsNeedingUpdates(_childFlows, _childFlowsToUpdateFlowRate, address(0));

        // Phase 3 — zero units and emit events
        for (uint256 i = 0; i < n; ) {
            emit IFlowEvents.RecipientRemoved(removedAddrs[i], recipientIds[i]);
            fs.removeFromPools(removedAddrs[i]);
            unchecked {
                ++i;
            }
        }
    }
}
