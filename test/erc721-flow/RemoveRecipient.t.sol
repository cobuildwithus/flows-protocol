// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { ERC721FlowTest } from "./ERC721Flow.t.sol";
import { IFlowEvents, IFlow } from "../../src/interfaces/IFlow.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";

contract RemoveRecipientsTest is ERC721FlowTest {
    function setUp() public override {
        super.setUp();
    }

    function testRemoveRecipient() public {
        address recipient = address(0x123);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));

        // Add a recipient first
        vm.prank(flow.owner());
        (, address recipientAddress) = flow.addRecipient(recipientId, recipient, recipientMetadata);

        // Test successful removal of a recipient
        vm.startPrank(flow.owner());
        vm.expectEmit(true, true, true, true);
        emit IFlowEvents.RecipientRemoved(recipientAddress, recipientId);
        flow.removeRecipient(recipientId);

        // Verify recipient was removed correctly
        FlowTypes.FlowRecipient memory storedRecipient = flow.getRecipientById(recipientId);
        assertEq(storedRecipient.recipient, recipient);
        assertEq(storedRecipient.removed, true);
        assertEq(flow.recipientExists(recipient), false);

        // Verify recipient count remains the same
        assertEq(flow.activeRecipientCount(), 0);
    }

    function testRemoveRecipientInvalidId() public {
        address recipient = address(0x123);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));

        // Add a recipient first
        vm.prank(flow.owner());
        flow.addRecipient(recipientId, recipient, recipientMetadata);

        // Test removing a recipient with an invalid ID (should revert)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.INVALID_RECIPIENT_ID.selector);
        flow.removeRecipient(bytes32(uint256(1))); // Using ID 1, which is invalid as we only added one recipient (ID 0)

        // Verify that the valid recipient (ID 0) still exists and is not removed
        FlowTypes.FlowRecipient memory storedRecipient = flow.getRecipientById(recipientId);
        assertEq(storedRecipient.recipient, recipient);
        assertEq(storedRecipient.removed, false);
    }

    function testRemoveRecipientAlreadyRemoved() public {
        address recipient = address(0x123);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));

        // Add a recipient
        vm.prank(flow.owner());
        flow.addRecipient(recipientId, recipient, recipientMetadata);

        // Remove the recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId);

        // Try to remove the same recipient again (should revert)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.RECIPIENT_ALREADY_REMOVED.selector);
        flow.removeRecipient(recipientId);
    }

    function testRemoveRecipientNonManager() public {
        address recipient = address(0x123);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));

        // Add a recipient
        vm.prank(flow.owner());
        flow.addRecipient(recipientId, recipient, recipientMetadata);

        // Test removing a recipient from a non-manager address (should revert)
        vm.prank(address(0xABC));
        vm.expectRevert(IFlow.SENDER_NOT_MANAGER.selector);
        flow.removeRecipient(recipientId);
    }
    function testRemoveMultipleRecipients() public {
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

        // Add recipients
        vm.startPrank(flow.owner());
        flow.addRecipient(recipientId1, recipient1, metadata1);
        flow.addRecipient(recipientId2, recipient2, metadata2);

        // Remove first recipient
        flow.removeRecipient(recipientId1);

        // Verify first recipient was removed
        FlowTypes.FlowRecipient memory storedRecipient1 = flow.getRecipientById(recipientId1);
        assertEq(storedRecipient1.recipient, recipient1);
        assertEq(storedRecipient1.removed, true);

        // Remove second recipient
        flow.removeRecipient(recipientId2);

        // Verify second recipient was removed
        FlowTypes.FlowRecipient memory storedRecipient2 = flow.getRecipientById(recipientId2);
        assertEq(storedRecipient2.recipient, recipient2);
        assertEq(storedRecipient2.removed, true);

        // Verify recipient count remains the same
        assertEq(flow.activeRecipientCount(), 0);
    }

    function testRemoveRecipientUpdateMemberUnits() public {
        address recipient = address(0x123);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));

        // Add a recipient
        vm.prank(flow.owner());
        flow.addRecipient(recipientId, recipient, recipientMetadata);

        // Cast a vote to give the recipient some member units
        uint256 tokenId = 0;
        bytes32[] memory recipientIds = new bytes32[](1);
        recipientIds[0] = recipientId;
        uint32[] memory percentAllocations = new uint32[](1);
        percentAllocations[0] = 1e6; // 100%
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(address(this));
        nounsToken.mint(address(this), tokenId);

        vm.prank(address(this));
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Check initial member units
        uint128 initialUnits = flow.bonusPool().getUnits(recipient);
        assertGt(initialUnits, 0);

        // Remove the recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId);

        // Check that member units have been updated (should be 0)
        uint128 finalUnits = flow.bonusPool().getUnits(recipient);
        assertEq(finalUnits, 0);
    }

    function testRemoveRecipientAndVoteAgain() public {
        address recipient = address(0x123);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));

        // Add a recipient
        vm.prank(flow.owner());
        flow.addRecipient(recipientId, recipient, recipientMetadata);

        // Remove the recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId);

        // Attempt to vote for the removed recipient
        uint256 tokenId = 0;
        bytes32[] memory recipientIds = new bytes32[](1);
        recipientIds[0] = recipientId;
        uint32[] memory percentAllocations = new uint32[](1);
        percentAllocations[0] = 1e6; // 100%
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(address(this));
        nounsToken.mint(address(this), tokenId);

        vm.expectRevert(IFlow.NOT_APPROVED_RECIPIENT.selector);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Verify that no votes were cast
        FlowTypes.VoteAllocation[] memory votes = flow.getVotesForTokenId(tokenId);
        assertEq(votes.length, 0);

        // Verify that member units remain at 0
        uint128 finalUnits = flow.bonusPool().getUnits(recipient);
        assertEq(finalUnits, 0);
    }

    function testVoteAfterRemovingRecipient() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);
        bytes32 recipientId1 = keccak256(abi.encodePacked(recipient1));
        bytes32 recipientId2 = keccak256(abi.encodePacked(recipient2));

        // Add two recipients
        vm.startPrank(flow.owner());
        flow.addRecipient(recipientId1, recipient1, recipientMetadata);
        flow.addRecipient(recipientId2, recipient2, recipientMetadata);
        vm.stopPrank();

        // Mint a token for voting
        uint256 tokenId = 0;
        vm.prank(address(this));
        nounsToken.mint(address(this), tokenId);

        // Vote for the first recipient
        bytes32[] memory recipientIds = new bytes32[](1);
        recipientIds[0] = recipientId1;
        uint32[] memory percentAllocations = new uint32[](1);
        percentAllocations[0] = 1e6; // 100%
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Verify the vote was cast
        FlowTypes.VoteAllocation[] memory votes = flow.getVotesForTokenId(tokenId);
        assertEq(votes.length, 1);
        assertEq(votes[0].recipientId, recipientId1);
        assertEq(votes[0].bps, 1e6);

        // Remove the first recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId1);

        // Vote for the second recipient
        recipientIds[0] = recipientId2;
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Verify the new vote was cast
        votes = flow.getVotesForTokenId(tokenId);
        assertEq(votes.length, 1);
        assertEq(votes[0].recipientId, recipientId2);
        assertEq(votes[0].bps, 1e6);

        // Verify member units
        uint128 units1 = flow.bonusPool().getUnits(recipient1);
        uint128 units2 = flow.bonusPool().getUnits(recipient2);
        assertEq(units1, 0);
        assertGt(units2, 0);
    }

    function testRemoveRecipientBaselineMemberUnits() public {
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

        // Add recipients
        vm.prank(flow.owner());
        flow.addRecipient(recipientId1, recipient1, metadata1);
        vm.prank(flow.owner());
        flow.addRecipient(recipientId2, recipient2, metadata2);

        // Check initial state
        uint128 initialTotalUnits = flow.baselinePool().getTotalUnits();
        assertEq(initialTotalUnits, flow.BASELINE_MEMBER_UNITS() * 2 + 1, "Initial total units incorrect");

        // Remove first recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId1);

        // Check units after removing first recipient
        uint128 unitsAfterRemove1 = flow.baselinePool().getTotalUnits();
        assertEq(
            unitsAfterRemove1,
            flow.BASELINE_MEMBER_UNITS() + 1,
            "Total units incorrect after removing first recipient"
        );
        assertEq(flow.baselinePool().getUnits(recipient1), 0, "Removed recipient should have 0 units");
        assertEq(
            flow.baselinePool().getUnits(recipient2),
            flow.BASELINE_MEMBER_UNITS(),
            "Remaining recipient should keep units"
        );

        // Try to remove the same recipient again (should not change anything)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.RECIPIENT_ALREADY_REMOVED.selector);
        flow.removeRecipient(recipientId1);
        assertEq(
            flow.baselinePool().getTotalUnits(),
            unitsAfterRemove1,
            "Total units should not change when removing already removed recipient"
        );

        // Remove second recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId2);

        // Check final state
        uint128 finalTotalUnits = flow.baselinePool().getTotalUnits();
        assertEq(finalTotalUnits, 1, "Final total units should be 1 (for address(this))");
        assertEq(flow.baselinePool().getUnits(recipient2), 0, "Second removed recipient should have 0 units");

        // Try to remove non-existent recipient (should revert)
        vm.prank(flow.owner());
        vm.expectRevert();
        flow.removeRecipient(bytes32(uint256(2)));

        // Add a new recipient and verify units are assigned correctly
        address recipient3 = address(0x789);
        bytes32 recipientId3 = keccak256(abi.encodePacked(recipient3));
        FlowTypes.RecipientMetadata memory metadata3 = FlowTypes.RecipientMetadata(
            "Recipient 3",
            "Description 3",
            "ipfs://image3",
            "Tagline 3",
            "https://recipient3.com"
        );
        vm.prank(flow.owner());
        flow.addRecipient(recipientId3, recipient3, metadata3);

        assertEq(
            flow.baselinePool().getTotalUnits(),
            flow.BASELINE_MEMBER_UNITS() + 1,
            "Total units incorrect after adding new recipient"
        );
        assertEq(
            flow.baselinePool().getUnits(recipient3),
            flow.BASELINE_MEMBER_UNITS(),
            "New recipient should have baseline member units"
        );
    }

    function testRemoveFlowRecipient() public {
        address flowManager1 = address(0x123);
        address flowManager2 = address(0x456);
        FlowTypes.RecipientMetadata memory metadata1 = FlowTypes.RecipientMetadata(
            "Flow Recipient 1",
            "Description 1",
            "ipfs://image1",
            "Tagline 1",
            "https://flowrecipient1.com"
        );
        FlowTypes.RecipientMetadata memory metadata2 = FlowTypes.RecipientMetadata(
            "Flow Recipient 2",
            "Description 2",
            "ipfs://image2",
            "Tagline 2",
            "https://flowrecipient2.com"
        );

        // Add flow recipients
        vm.startPrank(flow.owner());
        bytes32 recipientId1 = keccak256(abi.encodePacked(flowManager1));
        bytes32 recipientId2 = keccak256(abi.encodePacked(flowManager2));
        (, address flowRecipient1) = flow.addFlowRecipient(
            recipientId1,
            metadata1,
            flowManager1,
            address(0),
            bytes("")
        );
        (, address flowRecipient2) = flow.addFlowRecipient(
            recipientId2,
            metadata2,
            flowManager2,
            address(0),
            bytes("")
        );
        vm.stopPrank();

        // Check initial state
        uint128 initialTotalUnits = flow.baselinePool().getTotalUnits();
        assertEq(initialTotalUnits, flow.BASELINE_MEMBER_UNITS() * 2 + 1, "Initial total units incorrect");

        // Remove first flow recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId1);

        // Check units after removing first recipient
        uint128 unitsAfterRemove1 = flow.baselinePool().getTotalUnits();
        assertEq(
            unitsAfterRemove1,
            flow.BASELINE_MEMBER_UNITS() + 1,
            "Total units incorrect after removing first recipient"
        );
        assertEq(flow.baselinePool().getUnits(flowRecipient1), 0, "Removed recipient should have 0 units");
        assertEq(
            flow.baselinePool().getUnits(flowRecipient2),
            flow.BASELINE_MEMBER_UNITS(),
            "Remaining recipient should keep units"
        );

        // Try to remove the same recipient again (should not change anything)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.RECIPIENT_ALREADY_REMOVED.selector);
        flow.removeRecipient(recipientId1);
        assertEq(
            flow.baselinePool().getTotalUnits(),
            unitsAfterRemove1,
            "Total units should not change when removing already removed recipient"
        );

        // Remove second flow recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId2);

        // Check final state
        uint128 finalTotalUnits = flow.baselinePool().getTotalUnits();
        assertEq(finalTotalUnits, 1, "Final total units should be 1 (for address(this))");
        assertEq(flow.baselinePool().getUnits(flowRecipient2), 0, "Second removed recipient should have 0 units");

        // Try to remove non-existent recipient (should revert)
        vm.prank(flow.owner());
        vm.expectRevert();
        flow.removeRecipient(bytes32(uint256(2)));

        // Add a new flow recipient and verify units are assigned correctly
        address flowManager3 = address(0x789);
        FlowTypes.RecipientMetadata memory metadata3 = FlowTypes.RecipientMetadata(
            "Flow Recipient 3",
            "Description 3",
            "ipfs://image3",
            "Tagline 3",
            "https://flowrecipient3.com"
        );
        vm.prank(flow.owner());
        bytes32 recipientId3 = keccak256(abi.encodePacked(flowManager3));
        (, address flowRecipient3) = flow.addFlowRecipient(
            recipientId3,
            metadata3,
            flowManager3,
            address(0),
            bytes("")
        );

        assertEq(
            flow.baselinePool().getTotalUnits(),
            flow.BASELINE_MEMBER_UNITS() + 1,
            "Total units incorrect after adding new recipient"
        );
        assertEq(
            flow.baselinePool().getUnits(flowRecipient3),
            flow.BASELINE_MEMBER_UNITS(),
            "New recipient should have baseline member units"
        );
    }

    function testAddAndRemoveMultipleRecipients() public {
        int96 flowRate = 400e12;

        vm.pauseGasMetering();

        vm.prank(flow.owner());
        flow.setFlowRate(flowRate);

        uint256 numRecipients = 50;
        bytes32[] memory recipientIds = new bytes32[](numRecipients);
        address[] memory flowRecipients = new address[](numRecipients);

        vm.deal(address(flow.owner()), 1e30);
        vm.deal(address(this), 1e30);

        // Add 1000 recipients
        for (uint256 i = 0; i < numRecipients; i++) {
            address flowManager = address(uint160(i + 1));
            FlowTypes.RecipientMetadata memory metadata = FlowTypes.RecipientMetadata(
                string(abi.encodePacked("Flow Recipient ", i + 1)),
                string(abi.encodePacked("Description ", i + 1)),
                string(abi.encodePacked("ipfs://image", i + 1)),
                string(abi.encodePacked("Tagline ", i + 1)),
                string(abi.encodePacked("https://flowrecipient", i + 1, ".com"))
            );
            vm.prank(flow.owner());
            recipientIds[i] = keccak256(abi.encodePacked(flowManager));
            (, flowRecipients[i]) = flow.addFlowRecipient(
                recipientIds[i],
                metadata,
                flowManager,
                address(0),
                bytes("")
            );
        }

        // Verify all recipients were added correctly
        assertEq(
            flow.baselinePool().getTotalUnits(),
            flow.BASELINE_MEMBER_UNITS() * numRecipients + 1,
            "Total units incorrect after adding recipients"
        );

        // ensure all flow recipients have the correct flow rate
        for (uint256 i = 0; i < numRecipients; i++) {
            assertGt(flow.getMemberTotalFlowRate(flowRecipients[i]), 0);
        }

        // Remove all added recipients
        for (uint256 i = 0; i < numRecipients; i++) {
            vm.prank(flow.owner());
            flow.removeRecipient(recipientIds[i]);
        }

        // ensure flow rate stays consistent
        assertEq(flow.getTotalFlowRate(), flowRate);

        // Verify all recipients were removed correctly
        assertEq(flow.baselinePool().getTotalUnits(), 1, "Final total units should be 1 (for address(this))");

        for (uint256 i = 0; i < numRecipients; i++) {
            assertEq(flow.baselinePool().getUnits(flowRecipients[i]), 0, "Removed recipient should have 0 units");
        }
    }
}
