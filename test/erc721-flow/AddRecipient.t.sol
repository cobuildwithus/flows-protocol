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

    function testBulkAddRecipients() public {
        address recipient1 = address(0x111);
        address recipient2 = address(0x222);
        bytes32 id1 = keccak256(abi.encodePacked(recipient1));
        bytes32 id2 = keccak256(abi.encodePacked(recipient2));

        FlowTypes.RecipientMetadata[] memory metas = new FlowTypes.RecipientMetadata[](2);
        metas[0] = FlowTypes.RecipientMetadata("R1", "D1", "ipfs://1", "T1", "https://r1");
        metas[1] = FlowTypes.RecipientMetadata("R2", "D2", "ipfs://2", "T2", "https://r2");

        bytes32[] memory ids = new bytes32[](2);
        ids[0] = id1;
        ids[1] = id2;
        address[] memory recips = new address[](2);
        recips[0] = recipient1;
        recips[1] = recipient2;

        vm.startPrank(flow.owner());
        vm.expectEmit(true, true, true, true);
        emit IFlowEvents.RecipientCreated(
            id1,
            FlowTypes.FlowRecipient({
                recipientType: FlowTypes.RecipientType.ExternalAccount,
                removed: false,
                recipient: recipient1,
                metadata: metas[0]
            }),
            flow.owner()
        );
        vm.expectEmit(true, true, true, true);
        emit IFlowEvents.RecipientCreated(
            id2,
            FlowTypes.FlowRecipient({
                recipientType: FlowTypes.RecipientType.ExternalAccount,
                removed: false,
                recipient: recipient2,
                metadata: metas[1]
            }),
            flow.owner()
        );

        (bytes32[] memory returnedIds, address[] memory addedAddrs) = flow.bulkAddRecipients(ids, recips, metas);
        vm.stopPrank();

        assertEq(returnedIds.length, 2);
        assertEq(addedAddrs.length, 2);
        assertEq(flow.activeRecipientCount(), 2);

        // Baseline and bonus units assigned
        uint128 baselineUnits1 = flow.baselinePool().getUnits(recipient1);
        uint128 baselineUnits2 = flow.baselinePool().getUnits(recipient2);
        assertEq(baselineUnits1, flow.BASELINE_MEMBER_UNITS());
        assertEq(baselineUnits2, flow.BASELINE_MEMBER_UNITS());
        assertEq(flow.bonusPool().getUnits(recipient1), 10);
        assertEq(flow.bonusPool().getUnits(recipient2), 10);
    }

    function testBulkAddRecipients_ArrayLengthMismatch() public {
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = keccak256(abi.encodePacked(address(0x1)));
        ids[1] = keccak256(abi.encodePacked(address(0x2)));

        address[] memory recips = new address[](1);
        recips[0] = address(0x1);

        FlowTypes.RecipientMetadata[] memory metas = new FlowTypes.RecipientMetadata[](2);
        metas[0] = recipientMetadata;
        metas[1] = recipientMetadata;

        vm.prank(flow.owner());
        vm.expectRevert(IFlow.ARRAY_LENGTH_MISMATCH.selector);
        flow.bulkAddRecipients(ids, recips, metas);
    }

    function testBulkAddRecipients_TooFewRecipients() public {
        bytes32[] memory ids = new bytes32[](0);
        address[] memory recips = new address[](0);
        FlowTypes.RecipientMetadata[] memory metas = new FlowTypes.RecipientMetadata[](0);

        vm.prank(flow.owner());
        vm.expectRevert(IFlow.TOO_FEW_RECIPIENTS.selector);
        flow.bulkAddRecipients(ids, recips, metas);
    }

    function testBulkAddRecipients_NonManager() public {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = keccak256(abi.encodePacked(address(0x1)));
        address[] memory recips = new address[](1);
        recips[0] = address(0x1);
        FlowTypes.RecipientMetadata[] memory metas = new FlowTypes.RecipientMetadata[](1);
        metas[0] = recipientMetadata;

        vm.prank(address(0xABC));
        vm.expectRevert(IFlow.SENDER_NOT_MANAGER.selector);
        flow.bulkAddRecipients(ids, recips, metas);
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
        vm.startPrank(flow.owner());
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
            strategies
        );
        vm.stopPrank();

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
