// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { ERC721FlowTest } from "./ERC721Flow.t.sol";
import { IFlowEvents, IFlow } from "../../src/interfaces/IFlow.sol";
import { Flow } from "../../src/Flow.sol";
import { console } from "forge-std/console.sol";

contract DelegateVotingTest is ERC721FlowTest {
    function setUp() public override {
        super.setUp();
    }

    function testDelegateVoting() public {
        address tokenOwner = address(1);
        address delegate = address(2);
        uint256 tokenId = 0;

        // Mint token to owner
        nounsToken.mint(tokenOwner, tokenId);

        // Set up recipients
        address recipient1 = address(3);
        address recipient2 = address(4);
        vm.startPrank(manager);
        bytes32 recipientId1 = keccak256(abi.encodePacked(recipient1));
        bytes32 recipientId2 = keccak256(abi.encodePacked(recipient2));
        (bytes32 returnedRecipientId1, address recipientAddress1) = flow.addRecipient(
            recipientId1,
            recipient1,
            recipientMetadata
        );
        (bytes32 returnedRecipientId2, address recipientAddress2) = flow.addRecipient(
            recipientId2,
            recipient2,
            recipientMetadata
        );
        vm.stopPrank();

        // Prepare vote data
        bytes32[] memory recipientIds = new bytes32[](2);
        uint32[] memory percentAllocations = new uint32[](2);
        uint256[] memory tokenIds = new uint256[](1);

        recipientIds[0] = recipientId1;
        recipientIds[1] = recipientId2;
        percentAllocations[0] = 7e5; // 70%
        percentAllocations[1] = 3e5; // 30%
        tokenIds[0] = tokenId;

        // Try to vote with tokenOwner (should succeed)
        vm.prank(tokenOwner);
        allocateTokensWithWitnessHelper(tokenOwner, tokenIds, recipientIds, percentAllocations);

        // Try to vote with delegate (should fail)
        allocateTokensWithWitnessHelper(
            delegate,
            tokenIds,
            recipientIds,
            percentAllocations,
            abi.encodeWithSignature("NOT_ABLE_TO_ALLOCATE()")
        );

        // Delegate voting power
        vm.prank(tokenOwner);
        nounsToken.delegate(delegate);

        // Try to vote with tokenOwner (should now fail)
        vm.prank(tokenOwner);
        allocateTokensWithWitnessHelper(
            tokenOwner,
            tokenIds,
            recipientIds,
            percentAllocations,
            abi.encodeWithSignature("NOT_ABLE_TO_ALLOCATE()")
        );

        // Change vote allocations
        percentAllocations[0] = 4e5; // 40%
        percentAllocations[1] = 6e5; // 60%

        // Vote with delegate (should now succeed)
        vm.prank(delegate);
        allocateTokensWithWitnessHelper(delegate, tokenIds, recipientIds, percentAllocations);
    }

    function testMultiTokenDelegateVoting() public {
        address tokenOwner1 = address(1);
        address tokenOwner2 = address(2);
        address delegate = address(3);
        uint256 tokenId1 = 0;
        uint256 tokenId2 = 1;

        // Mint tokens to owners
        nounsToken.mint(tokenOwner1, tokenId1);
        nounsToken.mint(tokenOwner2, tokenId2);

        // Set up recipients
        address recipient1 = address(4);
        address recipient2 = address(5);
        vm.startPrank(manager);
        bytes32 recipientId1 = keccak256(abi.encodePacked(recipient1));
        bytes32 recipientId2 = keccak256(abi.encodePacked(recipient2));
        (bytes32 returnedRecipientId1, address recipientAddress1) = flow.addRecipient(
            recipientId1,
            recipient1,
            recipientMetadata
        );
        (bytes32 returnedRecipientId2, address recipientAddress2) = flow.addRecipient(
            recipientId2,
            recipient2,
            recipientMetadata
        );
        vm.stopPrank();

        // Prepare vote data
        bytes32[] memory recipientIds = new bytes32[](2);
        uint32[] memory percentAllocations = new uint32[](2);
        uint256[] memory tokenIds = new uint256[](2);

        recipientIds[0] = recipientId1;
        recipientIds[1] = recipientId2;
        percentAllocations[0] = 5e5; // 50%
        percentAllocations[1] = 5e5; // 50%
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        // Delegate voting power for both tokens
        vm.prank(tokenOwner1);
        nounsToken.delegate(delegate);
        vm.prank(tokenOwner2);
        nounsToken.delegate(delegate);

        // Vote with delegate for both tokens
        vm.prank(delegate);
        allocateTokensWithWitnessHelper(delegate, tokenIds, recipientIds, percentAllocations);

        // Check that the total units for each recipient reflect votes from both tokens
        uint128 recipient1Units = flow.bonusPool().getUnits(recipient1);
        uint128 recipient2Units = flow.bonusPool().getUnits(recipient2);

        assertGt(recipient1Units, 0);
        assertGt(recipient2Units, 0);
        assertEq(recipient1Units, recipient2Units);
    }
}
