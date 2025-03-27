// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { IFlowEvents, IFlow } from "../../src/interfaces/IFlow.sol";
import { ERC721Flow } from "../../src/ERC721Flow.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";
import { ERC721FlowTest } from "./ERC721Flow.t.sol";

contract FlowRecipientTest is ERC721FlowTest {
    function setUp() public override {
        super.setUp();
    }
    function testAddFlowRecipientParent() public {
        FlowTypes.RecipientMetadata memory metadata = FlowTypes.RecipientMetadata(
            "Flow Recipient",
            "A new Flow contract",
            "ipfs://image",
            "Flow Recipient Tagline",
            "https://flowrecipient.com"
        );
        address flowManager = address(0x123);
        bytes32 recipientId = keccak256(abi.encodePacked(flowManager));

        vm.prank(manager);
        (, address newFlowAddress) = flow.addFlowRecipient(recipientId, metadata, flowManager, address(0));

        ERC721Flow newFlow = ERC721Flow(newFlowAddress);

        // Transfer test tokens to the new Flow contract
        _transferTestTokenToFlow(newFlowAddress, 1e6 * 10 ** 18);

        // Check that the parent of the new Flow contract is set correctly
        assertEq(newFlow.parent(), address(flow), "Parent of new Flow contract should be the original Flow contract");

        // Test that parent can call setFlowRate
        int96 newFlowRate = 1000;
        vm.prank(address(flow));
        newFlow.setFlowRate(newFlowRate);

        // Verify the flow rate was updated
        assertEq(newFlow.getTotalFlowRate(), newFlowRate, "Flow rate should be updated by parent");
    }

    function testAddFlowRecipient() public {
        FlowTypes.RecipientMetadata memory metadata = FlowTypes.RecipientMetadata(
            "Flow Recipient",
            "A new Flow contract",
            "ipfs://image",
            "Flow Recipient Tagline",
            "https://flowrecipient.com"
        );
        address flowManager = address(0x123); // New flow manager address
        bytes32 recipientId = keccak256(abi.encodePacked(flowManager));

        vm.startPrank(flow.owner());

        // Test successful addition of a Flow recipient
        vm.expectEmit(false, true, false, false);
        emit IFlowEvents.RecipientCreated(
            0,
            FlowTypes.FlowRecipient({
                recipientType: FlowTypes.RecipientType.FlowContract,
                removed: false,
                recipient: address(0),
                metadata: metadata
            }),
            flow.owner()
        );
        (bytes32 returnedRecipientId, address newFlowAddress) = flow.addFlowRecipient(
            recipientId,
            metadata,
            flowManager,
            address(0)
        );

        assertEq(returnedRecipientId, recipientId);
        assertNotEq(newFlowAddress, address(0));

        // Verify recipient was added correctly
        assertNotEq(newFlowAddress, address(0));
        FlowTypes.FlowRecipient memory storedRecipient = flow.getRecipientById(recipientId);
        assertEq(storedRecipient.recipient, newFlowAddress);
        assertEq(storedRecipient.removed, false);
        assertEq(uint8(storedRecipient.recipientType), uint8(FlowTypes.RecipientType.FlowContract));
        assertEq(storedRecipient.metadata.title, metadata.title);
        assertEq(storedRecipient.metadata.description, metadata.description);
        assertEq(storedRecipient.metadata.image, metadata.image);
        assertEq(storedRecipient.metadata.tagline, metadata.tagline);
        assertEq(storedRecipient.metadata.url, metadata.url);

        // Verify recipient count increased
        assertEq(flow.activeRecipientCount(), 1);

        // Check the newly created Flow contract fields
        ERC721Flow newFlow = ERC721Flow(newFlowAddress);
        assertEq(address(newFlow.erc721Votes()), address(nounsToken));
        assertEq(address(newFlow.superToken()), address(superToken));
        assertEq(newFlow.flowImpl(), flow.flowImpl());
        assertEq(newFlow.manager(), flowManager); // Check that the manager is set to the new flowManager
        assertEq(newFlow.tokenVoteWeight(), flow.tokenVoteWeight());
        FlowTypes.RecipientMetadata memory newFlowMetadata = newFlow.flowMetadata();
        assertEq(newFlowMetadata.title, metadata.title);
        assertEq(newFlowMetadata.description, metadata.description);
        assertEq(newFlowMetadata.image, metadata.image);
        assertEq(newFlowMetadata.tagline, metadata.tagline);
        assertEq(newFlowMetadata.url, metadata.url);
        vm.stopPrank();

        // Verify that ownership has been accepted
        assertEq(newFlow.owner(), flow.owner());

        vm.stopPrank();
    }

    function testAddFlowRecipientEmptyManager() public {
        FlowTypes.RecipientMetadata memory metadata = FlowTypes.RecipientMetadata(
            "Flow Recipient",
            "A new Flow contract",
            "ipfs://image",
            "Flow Recipient Tagline",
            "https://flowrecipient.com"
        );
        address emptyManager = address(0);
        bytes32 recipientId = keccak256(abi.encodePacked(emptyManager));

        vm.startPrank(flow.owner());

        vm.expectRevert(IFlow.ADDRESS_ZERO.selector);
        flow.addFlowRecipient(recipientId, metadata, emptyManager, address(0));

        vm.stopPrank();
    }

    function testAddFlowRecipientEmptyMetadata() public {
        FlowTypes.RecipientMetadata memory emptyMetadata = FlowTypes.RecipientMetadata("", "", "", "", "");
        address flowManager = address(0x123);
        bytes32 recipientId = keccak256(abi.encodePacked(flowManager));

        vm.prank(flow.owner());
        vm.expectRevert(IFlow.INVALID_METADATA.selector);
        flow.addFlowRecipient(recipientId, emptyMetadata, flowManager, address(0));
    }

    function testAddFlowRecipientNonManager() public {
        FlowTypes.RecipientMetadata memory metadata = FlowTypes.RecipientMetadata(
            "Flow Recipient",
            "A new Flow contract",
            "ipfs://image",
            "Flow Recipient Tagline",
            "https://flowrecipient.com"
        );
        address flowManager = address(0x123);
        bytes32 recipientId = keccak256(abi.encodePacked(flowManager));

        vm.prank(address(0xABC));
        vm.expectRevert(IFlow.SENDER_NOT_MANAGER.selector);
        flow.addFlowRecipient(recipientId, metadata, flowManager, address(0));
    }

    function testAddMultipleFlowRecipients() public {
        FlowTypes.RecipientMetadata memory metadata1 = FlowTypes.RecipientMetadata(
            "Flow Recipient 1",
            "First Flow contract",
            "ipfs://image1",
            "Tagline 1",
            "https://flow1.com"
        );
        FlowTypes.RecipientMetadata memory metadata2 = FlowTypes.RecipientMetadata(
            "Flow Recipient 2",
            "Second Flow contract",
            "ipfs://image2",
            "Tagline 2",
            "https://flow2.com"
        );
        address flowManager1 = address(0x123);
        address flowManager2 = address(0x456);
        bytes32 recipientId1 = keccak256(abi.encodePacked(flowManager1));
        bytes32 recipientId2 = keccak256(abi.encodePacked(flowManager2));

        vm.startPrank(flow.owner());

        (, address newFlowAddress1) = flow.addFlowRecipient(recipientId1, metadata1, flowManager1, address(0));
        (, address newFlowAddress2) = flow.addFlowRecipient(recipientId2, metadata2, flowManager2, address(0));

        assertNotEq(newFlowAddress1, newFlowAddress2);
        assertEq(flow.activeRecipientCount(), 2);

        vm.stopPrank();
    }
}
