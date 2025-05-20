// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { IFlowEvents, IFlow } from "../../src/interfaces/IFlow.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";
import { ERC721FlowTest } from "./ERC721Flow.t.sol";

contract AddRecipientsTest is ERC721FlowTest {
    function setUp() public override {
        super.setUp();
    }

    function testAddDuplicateRecipientId() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);
        bytes32 recipientId = keccak256(abi.encodePacked("testRecipient"));

        // Add the first recipient
        vm.startPrank(flow.owner());
        flow.addRecipient(recipientId, recipient1, recipientMetadata);

        // Attempt to add a second recipient with the same recipientId
        vm.expectRevert(IFlow.RECIPIENT_ALREADY_EXISTS.selector);
        flow.addRecipient(recipientId, recipient2, recipientMetadata);
        vm.stopPrank();

        // Verify only the first recipient was added
        assertEq(flow.activeRecipientCount(), 1);
        FlowTypes.FlowRecipient memory storedRecipient = flow.getRecipientById(recipientId);
        assertEq(storedRecipient.recipient, recipient1);
    }

    function testAddRecipient() public {
        address recipient = address(0x123);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));
        // Test successful addition of a recipient
        vm.startPrank(flow.owner());
        vm.expectEmit(true, true, true, true);
        emit IFlowEvents.RecipientCreated(
            recipientId,
            FlowTypes.FlowRecipient({
                recipientType: FlowTypes.RecipientType.ExternalAccount,
                removed: false,
                recipient: recipient,
                metadata: recipientMetadata
            }),
            flow.owner()
        );
        (bytes32 returnedRecipientId, address returnedRecipient) = flow.addRecipient(
            recipientId,
            recipient,
            recipientMetadata
        );

        // Verify recipient was added correctly
        FlowTypes.FlowRecipient memory storedRecipient = flow.getRecipientById(returnedRecipientId);
        assertEq(storedRecipient.recipient, recipient);
        assertEq(storedRecipient.removed, false);
        assertEq(uint8(storedRecipient.recipientType), uint8(FlowTypes.RecipientType.ExternalAccount));
        assertEq(storedRecipient.metadata.title, recipientMetadata.title);
        assertEq(storedRecipient.metadata.description, recipientMetadata.description);
        assertEq(storedRecipient.metadata.image, recipientMetadata.image);
        assertEq(flow.recipientExists(recipient), true);

        // Verify recipient count increased
        assertEq(flow.activeRecipientCount(), 1);
    }

    function testAddRecipientZeroAddress() public {
        // Test adding a zero address recipient (should revert)
        bytes32 recipientId = keccak256(abi.encodePacked(address(0)));
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.ADDRESS_ZERO.selector);
        flow.addRecipient(recipientId, address(0), recipientMetadata);
    }

    function testAddRecipientEmptyMetadata() public {
        address recipient = address(0x123);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));

        // Test adding a recipient with empty metadata (should revert)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.INVALID_METADATA.selector);
        flow.addRecipient(recipientId, recipient, FlowTypes.RecipientMetadata("", "", "", "", ""));
    }

    function testAddRecipientNonManager() public {
        address recipient = address(0x123);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));

        // Test adding a recipient from a non-manager address (should revert)
        vm.prank(address(0xABC));
        vm.expectRevert(IFlow.SENDER_NOT_MANAGER.selector);
        flow.addRecipient(recipientId, recipient, recipientMetadata);
    }

    function testAddMultipleRecipients() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);
        bytes32 recipientId1 = keccak256(abi.encodePacked(recipient1));
        bytes32 recipientId2 = keccak256(abi.encodePacked(recipient2));
        FlowTypes.RecipientMetadata memory metadata1 = FlowTypes.RecipientMetadata(
            "Recipient 1",
            "Description 1",
            "ipfs://image1",
            "Tagline 1",
            "https://recipient1.com"
        );
        FlowTypes.RecipientMetadata memory metadata2 = FlowTypes.RecipientMetadata(
            "Recipient 2",
            "Description 2",
            "ipfs://image2",
            "Tagline 2",
            "https://recipient2.com"
        );

        // Add first recipient
        vm.prank(flow.owner());
        (bytes32 returnedRecipientId1, ) = flow.addRecipient(recipientId1, recipient1, metadata1);

        // Add second recipient
        vm.prank(flow.owner());
        (bytes32 returnedRecipientId2, ) = flow.addRecipient(recipientId2, recipient2, metadata2);

        // Verify both recipients were added correctly
        assertEq(flow.activeRecipientCount(), 2);

        FlowTypes.FlowRecipient memory storedRecipient1 = flow.getRecipientById(returnedRecipientId1);
        FlowTypes.FlowRecipient memory storedRecipient2 = flow.getRecipientById(returnedRecipientId2);

        assertEq(storedRecipient1.recipient, recipient1);
        assertEq(storedRecipient2.recipient, recipient2);
        assertEq(storedRecipient1.metadata.title, metadata1.title);
        assertEq(storedRecipient2.metadata.title, metadata2.title);
    }

    function testBaselineMemberUnitsAfterAddingRecipients() public {
        address externalRecipient = address(0x123);
        bytes32 externalRecipientId = keccak256(abi.encodePacked(externalRecipient));
        FlowTypes.RecipientMetadata memory externalMetadata = FlowTypes.RecipientMetadata(
            "External Recipient",
            "Description",
            "ipfs://image1",
            "External Tagline",
            "https://external.com"
        );

        // Add external recipient
        vm.prank(flow.owner());
        flow.addRecipient(externalRecipientId, externalRecipient, externalMetadata);

        bytes32 flowRecipientId = keccak256(abi.encodePacked(flow.owner()));

        // Add flow recipient
        vm.prank(flow.owner());
        (, address flowRecipient) = flow.addFlowRecipient(
            flowRecipientId,
            FlowTypes.RecipientMetadata(
                "Flow Recipient",
                "Description",
                "ipfs://image2",
                "Flow Tagline",
                "https://flow.com"
            ),
            address(0x456), // flowManager address
            address(0),
            abi.encode(flow.flowImpl(), flow.erc721Votes())
        );

        // Check baseline member units for external recipient
        uint128 externalRecipientUnits = flow.baselinePool().getUnits(externalRecipient);
        assertEq(
            externalRecipientUnits,
            flow.BASELINE_MEMBER_UNITS(),
            "External recipient should have baseline member units"
        );

        // Check baseline member units for flow recipient
        uint128 flowRecipientUnits = flow.baselinePool().getUnits(flowRecipient);
        assertEq(flowRecipientUnits, flow.BASELINE_MEMBER_UNITS(), "Flow recipient should have baseline member units");

        // Verify total units in baseline pool
        uint128 totalUnits = flow.baselinePool().getTotalUnits();
        assertEq(
            totalUnits,
            flow.BASELINE_MEMBER_UNITS() * 2 + 1,
            "Total units should be 2 * BASELINE_MEMBER_UNITS + 1 (for address(this))"
        );
    }

    function testAddDuplicateRecipient() public {
        address recipient = address(0x123);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));
        FlowTypes.RecipientMetadata memory metadata = FlowTypes.RecipientMetadata({
            title: "Recipient",
            description: "Description",
            image: "ipfs://image",
            tagline: "Test Tagline",
            url: "https://example.com"
        });

        // Add recipient for the first time
        vm.prank(flow.owner());
        flow.addRecipient(recipientId, recipient, metadata);

        // Attempt to add the same recipient again
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.RECIPIENT_ALREADY_EXISTS.selector);
        flow.addRecipient(recipientId, recipient, metadata);

        // Verify recipient count hasn't changed
        assertEq(flow.activeRecipientCount(), 1, "Recipient count should still be 1");
    }
}
