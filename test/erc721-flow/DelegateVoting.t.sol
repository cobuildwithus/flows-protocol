// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import {ERC721FlowTest} from "./ERC721Flow.t.sol";
import {IFlowEvents, IFlow} from "../../src/interfaces/IFlow.sol";
import {Flow} from "../../src/Flow.sol";
import {MockERC721} from "../mocks/MockERC721.sol";
import {console} from "forge-std/console.sol";

contract DelegateVotingTest is ERC721FlowTest {

    function setUp() override public {
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
        flow.addRecipient(recipient1, recipientMetadata);
        flow.addRecipient(recipient2, recipientMetadata);
        vm.stopPrank();

        // Prepare vote data
        uint256[] memory recipientIds = new uint256[](2);
        uint32[] memory percentAllocations = new uint32[](2);
        uint256[] memory tokenIds = new uint256[](1);

        recipientIds[0] = 0;
        recipientIds[1] = 1;
        percentAllocations[0] = 7e5; // 70%
        percentAllocations[1] = 3e5; // 30%
        tokenIds[0] = tokenId;

        // Try to vote with tokenOwner (should succeed)
        vm.prank(tokenOwner);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Verify vote allocations
        Flow.VoteAllocation[] memory voteAllocations = flow.getVotesForTokenId(tokenId);
        assertEq(voteAllocations.length, 2);
        assertEq(voteAllocations[0].recipientId, 0);
        assertEq(voteAllocations[0].bps, 7e5);
        assertEq(voteAllocations[1].recipientId, 1);
        assertEq(voteAllocations[1].bps, 3e5);

        // Try to vote with delegate (should fail)
        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSignature("NOT_ABLE_TO_VOTE_WITH_TOKEN()"));
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Delegate voting power
        vm.prank(tokenOwner);
        nounsToken.delegate(delegate);

        // Try to vote with tokenOwner (should now fail)
        vm.prank(tokenOwner);
        vm.expectRevert(abi.encodeWithSignature("NOT_ABLE_TO_VOTE_WITH_TOKEN()"));
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Change vote allocations
        percentAllocations[0] = 4e5; // 40%
        percentAllocations[1] = 6e5; // 60%

        // Vote with delegate (should now succeed)
        vm.prank(delegate);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Verify new vote allocations
        voteAllocations = flow.getVotesForTokenId(tokenId);
        assertEq(voteAllocations.length, 2);
        assertEq(voteAllocations[0].recipientId, 0);
        assertEq(voteAllocations[0].bps, 4e5);
        assertEq(voteAllocations[1].recipientId, 1);
        assertEq(voteAllocations[1].bps, 6e5);
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
        flow.addRecipient(recipient1, recipientMetadata);
        flow.addRecipient(recipient2, recipientMetadata);
        vm.stopPrank();

        // Prepare vote data
        uint256[] memory recipientIds = new uint256[](2);
        uint32[] memory percentAllocations = new uint32[](2);
        uint256[] memory tokenIds = new uint256[](2);

        recipientIds[0] = 0;
        recipientIds[1] = 1;
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
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Verify vote allocations for both tokens
        Flow.VoteAllocation[] memory voteAllocations1 = flow.getVotesForTokenId(tokenId1);
        Flow.VoteAllocation[] memory voteAllocations2 = flow.getVotesForTokenId(tokenId2);

        assertEq(voteAllocations1.length, 2);
        assertEq(voteAllocations1[0].recipientId, 0);
        assertEq(voteAllocations1[0].bps, 5e5);
        assertEq(voteAllocations1[1].recipientId, 1);
        assertEq(voteAllocations1[1].bps, 5e5);

        assertEq(voteAllocations2.length, 2);
        assertEq(voteAllocations2[0].recipientId, 0);
        assertEq(voteAllocations2[0].bps, 5e5);
        assertEq(voteAllocations2[1].recipientId, 1);
        assertEq(voteAllocations2[1].bps, 5e5);

        // Check that the total units for each recipient reflect votes from both tokens
        uint128 recipient1Units = flow.bonusPool().getUnits(recipient1);
        uint128 recipient2Units = flow.bonusPool().getUnits(recipient2);

        assertGt(recipient1Units, 0);
        assertGt(recipient2Units, 0);
        assertEq(recipient1Units, recipient2Units);
    }
}
