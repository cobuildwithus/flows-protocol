// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { FlowTCRTest } from "./FlowTCR.t.sol";
import { IGeneralizedTCR } from "../../src/tcr/interfaces/IGeneralizedTCR.sol";
import { IArbitrable } from "../../src/tcr/interfaces/IArbitrable.sol";
import { IArbitrator } from "../../src/tcr/interfaces/IArbitrator.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";

contract BasicTCRTest is FlowTCRTest {
    // Test Cases

    /**
     * @dev Tests the submission of an item to the TCR
     * @notice This test performs the following steps:
     * 1. Submits an item to the TCR
     * 2. Retrieves the item information
     * 3. Verifies that the item data matches the submitted data
     * 4. Checks that the item status is set to RegistrationRequested
     * 5. Ensures that the number of requests for the item is 1
     */
    function testItemSubmission() public {
        bytes32 itemID = submitItem(EXTERNAL_ACCOUNT_ITEM_DATA, requester);
        bytes32 itemID2 = submitItem(FLOW_RECIPIENT_ITEM_DATA, requester);

        (bytes memory data, IGeneralizedTCR.Status status, uint256 numberOfRequests) = flowTCR.getItemInfo(itemID);
        (bytes memory data2, IGeneralizedTCR.Status status2, uint256 numberOfRequests2) = flowTCR.getItemInfo(itemID2);

        assertEq(data, EXTERNAL_ACCOUNT_ITEM_DATA);
        assertEq(uint256(status), uint256(IGeneralizedTCR.Status.RegistrationRequested));
        assertEq(numberOfRequests, 1);
        assertEq(data2, FLOW_RECIPIENT_ITEM_DATA);
        assertEq(uint256(status2), uint256(IGeneralizedTCR.Status.RegistrationRequested));
        assertEq(numberOfRequests2, 1);
    }

    /**
     * @dev Tests the challenging of an item in the TCR
     * @notice This test performs the following steps:
     * 1. Submits an item to the TCR
     * 2. Challenges the submitted item
     * 3. Retrieves the request information
     * 4. Verifies various aspects of the challenge, including:
     *    - The item is marked as disputed
     *    - The requester and challenger addresses are correct
     *    - The number of rounds is 1
     *    - The request is not yet resolved
     *    - The arbitrator address is correct
     *    - The arbitrator extra data is correct
     *    - The meta evidence ID is 0
     * 5. Retrieves the item information again
     * 6. Verifies that the item status is still RegistrationRequested
     * 7. Ensures that the number of requests for the item is still 1
     */
    function testItemChallenge() public {
        bytes32 itemID = submitItem(EXTERNAL_ACCOUNT_ITEM_DATA, requester);
        challengeItem(itemID, challenger);

        (
            bool disputed,
            ,
            ,
            bool resolved,
            address[3] memory parties,
            uint256 numberOfRounds,
            ,
            IArbitrator erc20VotesArbitrator,
            bytes memory arbitratorExtraData,
            uint256 metaEvidenceID
        ) = flowTCR.getRequestInfo(itemID, 0);

        assertTrue(disputed, "Item should be disputed after challenge");
        assertEq(parties[uint256(IArbitrable.Party.Requester)], requester, "Requester should be correct");
        assertEq(parties[uint256(IArbitrable.Party.Challenger)], challenger, "Challenger should be correct");
        assertEq(numberOfRounds, 1, "Number of rounds should be 1"); // no new round is made after challenge
        assertFalse(resolved, "Request should not be resolved yet");
        assertEq(address(erc20VotesArbitrator), address(arbitrator), "Arbitrator should be correct");
        assertEq(arbitratorExtraData, ARBITRATOR_EXTRA_DATA, "Arbitrator extra data should be correct");
        assertEq(metaEvidenceID, 0, "Meta evidence ID should be 0");

        (bytes memory data, IGeneralizedTCR.Status status, uint256 numberOfRequests) = flowTCR.getItemInfo(itemID);

        assertEq(data, EXTERNAL_ACCOUNT_ITEM_DATA, "Item data should match");
        assertEq(
            uint256(status),
            uint256(IGeneralizedTCR.Status.RegistrationRequested),
            "Status should be RegistrationRequested"
        );
        assertEq(numberOfRequests, 1, "Number of requests should be 1");
    }

    /**
     * @dev Helper function to test item registration after challenge period
     * @param itemData The data of the item to be registered
     */
    function _testItemRegistrationAfterChallengePeriod(bytes memory itemData) internal {
        bytes32 itemID = submitItem(itemData, requester);

        advanceTime(CHALLENGE_PERIOD + 1);

        flowTCR.executeRequest(itemID);

        (bytes memory data, IGeneralizedTCR.Status status, uint256 numberOfRequests) = flowTCR.getItemInfo(itemID);

        assertEq(data, itemData);
        assertEq(uint256(status), uint256(IGeneralizedTCR.Status.Registered));
        assertEq(numberOfRequests, 1);

        (
            address recipientAddress,
            FlowTypes.RecipientMetadata memory metadata,
            FlowTypes.RecipientType recipientType
        ) = abi.decode(itemData, (address, FlowTypes.RecipientMetadata, FlowTypes.RecipientType));

        if (recipientType == FlowTypes.RecipientType.ExternalAccount) {
            bytes32 recipientId = itemID;
            assertTrue(
                flow.recipientExists(recipientAddress),
                "Flow recipient should be created for the registered item"
            );
            FlowTypes.FlowRecipient memory storedRecipient = flow.getRecipientById(recipientId);
            assertEq(
                storedRecipient.recipient,
                recipientAddress,
                "Flow recipient address should match the one in itemData"
            );
            assertGt(flow.getMemberTotalFlowRate(recipientAddress), 0, "Member units should be greater than 0");
        } else if (recipientType == FlowTypes.RecipientType.FlowContract) {
            // get flowRecipientId from itemID
            bytes32 flowRecipientId = itemID;
            FlowTypes.FlowRecipient memory storedRecipient = flow.getRecipientById(flowRecipientId);
            assertTrue(
                storedRecipient.recipientType == FlowTypes.RecipientType.FlowContract,
                "Recipient type should be FlowContract"
            );
            assertNotEq(storedRecipient.recipient, address(0), "Flow contract address should not be zero");
            assertTrue(
                flow.recipientExists(storedRecipient.recipient),
                "Flow recipient should be created for the registered item"
            );
        }
    }

    /**
     * @dev Tests the registration of an external account item after the challenge period has passed
     */
    function testExternalAccountItemRegistrationAfterChallengePeriod() public {
        _testItemRegistrationAfterChallengePeriod(EXTERNAL_ACCOUNT_ITEM_DATA);
    }

    /**
     * @dev Tests the registration of a flow contract item after the challenge period has passed
     */
    function testFlowContractItemRegistrationAfterChallengePeriod() public {
        _testItemRegistrationAfterChallengePeriod(FLOW_RECIPIENT_ITEM_DATA);
    }

    /**
     * @dev Tests the basic flow of item submission, challenge, and registration
     * @param _itemData The data of the item to be submitted
     * @notice This test performs the following steps:
     * 1. Submits an item to the TCR
     * 2. Verifies the initial state of the item (RegistrationRequested)
     * 3. Challenges the item
     * 4. Verifies the state after challenge (disputed, not resolved)
     * 5. Advances time beyond the challenge period
     * 6. Executes the request to finalize the registration
     * 7. Verifies the final state of the item (Registered)
     */
    function _testBasicFlow(bytes memory _itemData) internal {
        // Submit an item
        bytes32 itemID = submitItem(_itemData, requester);

        // Check initial state
        (bytes memory data, IGeneralizedTCR.Status status, uint256 numberOfRequests) = flowTCR.getItemInfo(itemID);
        assertEq(data, _itemData, "Item data should match");
        assertEq(
            uint256(status),
            uint256(IGeneralizedTCR.Status.RegistrationRequested),
            "Status should be RegistrationRequested"
        );
        assertEq(numberOfRequests, 1, "Number of requests should be 1");

        // Challenge the item
        challengeItem(itemID, challenger);

        // Check state after challenge
        (
            bool disputed,
            uint256 disputeID,
            ,
            bool resolved,
            address[3] memory parties,
            uint256 numberOfRounds,
            ,
            ,
            ,

        ) = flowTCR.getRequestInfo(itemID, 0);

        assertTrue(disputed, "Item should be disputed after challenge");
        assertEq(parties[uint256(IArbitrable.Party.Requester)], requester, "Requester should be correct");
        assertEq(parties[uint256(IArbitrable.Party.Challenger)], challenger, "Challenger should be correct");
        assertEq(numberOfRounds, 1, "Number of rounds should be 1"); // no new round is made after challenge
        assertFalse(resolved, "Request should not be resolved yet");

        voteAndExecute(disputeID, IArbitrable.Party.Requester);

        // Check if the dispute is resolved
        (, , , bool requestResolved, , , IArbitrable.Party ruling, , , ) = flowTCR.getRequestInfo(itemID, 0);
        assertTrue(requestResolved, "Dispute should be resolved");
        assertEq(uint256(ruling), uint256(IArbitrable.Party.Requester), "Ruling should be in favor of the requester");

        advanceTime(CHALLENGE_PERIOD + 1);
        vm.expectRevert(IGeneralizedTCR.REQUEST_MUST_NOT_BE_DISPUTED.selector);
        flowTCR.executeRequest(itemID);

        // Check final state
        (data, status, numberOfRequests) = flowTCR.getItemInfo(itemID);
        assertEq(data, _itemData, "Item data should still match");
        assertEq(numberOfRequests, 1, "Number of requests should still be 1");
        assertEq(uint256(status), uint256(IGeneralizedTCR.Status.Registered), "Status should be Registered");

        // Decode the item data
        (address recipientAddress, , FlowTypes.RecipientType recipientType) = abi.decode(
            _itemData,
            (address, FlowTypes.RecipientMetadata, FlowTypes.RecipientType)
        );

        if (recipientType == FlowTypes.RecipientType.ExternalAccount) {
            bytes32 recipientId = itemID;

            assertTrue(
                flow.recipientExists(recipientAddress),
                "Flow recipient should be created for the registered item"
            );
            FlowTypes.FlowRecipient memory storedRecipient = flow.getRecipientById(recipientId);
            assertEq(
                storedRecipient.recipient,
                recipientAddress,
                "Flow recipient address should match the one in item data"
            );
            assertGt(flow.getMemberTotalFlowRate(recipientAddress), 0, "Member units should be greater than 0");
        } else if (recipientType == FlowTypes.RecipientType.FlowContract) {
            bytes32 flowRecipientId = itemID;
            FlowTypes.FlowRecipient memory storedRecipient = flow.getRecipientById(flowRecipientId);
            assertTrue(
                storedRecipient.recipientType == FlowTypes.RecipientType.FlowContract,
                "Recipient type should be FlowContract"
            );
            assertNotEq(storedRecipient.recipient, address(0), "Flow contract address should not be zero");
            assertTrue(
                flow.recipientExists(storedRecipient.recipient),
                "Flow recipient should be created for the registered item"
            );
        }
    }

    /**
     * @dev Tests the basic flow for an external account item
     */
    function testBasicFlowExternalAccount() public {
        _testBasicFlow(EXTERNAL_ACCOUNT_ITEM_DATA);
    }

    /**
     * @dev Tests the basic flow for a flow contract item
     */
    function testBasicFlowFlowContract() public {
        _testBasicFlow(FLOW_RECIPIENT_ITEM_DATA);
    }
}
