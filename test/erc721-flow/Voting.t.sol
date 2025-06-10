// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { ERC721FlowTest } from "./ERC721Flow.t.sol";
import { IFlowEvents, IFlow } from "../../src/interfaces/IFlow.sol";
import { Flow } from "../../src/Flow.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { console } from "forge-std/console.sol";

contract VotingFlowTest is ERC721FlowTest {
    function setUp() public override {
        super.setUp();
    }

    function test__RecipientVotesCleared() public {
        address voter1 = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter1, tokenId);

        address recipient = address(3);
        address recipient2 = address(4);
        vm.startPrank(manager);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));
        bytes32 recipientId2 = keccak256(abi.encodePacked(recipient2));
        flow.addRecipient(recipientId, recipient, recipientMetadata);
        flow.addRecipient(recipientId2, recipient2, recipientMetadata);
        vm.stopPrank();

        bytes32[] memory recipientIds = new bytes32[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        percentAllocations[0] = 1e6;
        tokenIds[0] = tokenId;
        recipientIds[0] = recipientId;

        vm.prank(voter1);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        // get current member units of the pool
        uint128 currentUnits = flow.bonusPool().getUnits(recipient);

        assertGt(currentUnits, 0);

        recipientIds[0] = recipientId2;

        vm.prank(voter1);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        uint128 recipient2Units = flow.bonusPool().getUnits(recipient2);

        assertGt(recipient2Units, 0);

        assertEq(flow.bonusPool().getUnits(recipient), 10); // 10 units for each recipient in case there are no votes yet, everyone will split the bonus salary
    }

    function test__RecipientVotesCleared_MultiToken() public {
        address voter1 = address(1);
        address voter2 = address(2);
        uint256 tokenId = 0;
        uint256 tokenId2 = 1;

        nounsToken.mint(voter1, tokenId);
        nounsToken.mint(voter2, tokenId2);

        address recipient = address(3);
        address recipient2 = address(4);
        vm.startPrank(manager);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));
        bytes32 recipientId2 = keccak256(abi.encodePacked(recipient2));
        flow.addRecipient(recipientId, recipient, recipientMetadata);
        flow.addRecipient(recipientId2, recipient2, recipientMetadata);
        vm.stopPrank();

        bytes32[] memory recipientIds = new bytes32[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory tokenIds2 = new uint256[](1);

        percentAllocations[0] = 1e6;
        tokenIds[0] = tokenId;
        tokenIds2[0] = tokenId2;
        recipientIds[0] = recipientId;

        vm.startPrank(voter2);
        flow.allocate(_prepTokens(tokenIds2), recipientIds, percentAllocations);
        vm.stopPrank();

        // get current member units of the pool
        uint128 originalUnits = flow.bonusPool().getUnits(recipient);

        assertGt(originalUnits, 0);

        vm.startPrank(voter1);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);
        vm.stopPrank();

        uint128 secondVoteUnits = flow.bonusPool().getUnits(recipient);

        assertGt(secondVoteUnits, originalUnits);

        bytes32[] memory newRecipientIds = new bytes32[](1);
        newRecipientIds[0] = recipientId2;

        vm.startPrank(voter1);
        flow.allocate(_prepTokens(tokenIds), newRecipientIds, percentAllocations);
        vm.stopPrank();

        uint128 recipient2Units = flow.bonusPool().getUnits(recipient2);
        assertGt(recipient2Units, 0);

        assertEq(flow.bonusPool().getUnits(recipient), originalUnits);
    }

    function test__AllocationStructForMultipleRecipients(uint32 splitPercentage) public {
        // Step 1: Ensure splitPercentage is within valid range
        splitPercentage = uint32(bound(uint256(splitPercentage), 1, 1e6 - 1));

        // Step 2: Set up test environment
        address voter = address(1);
        uint256 tokenId = 0;
        nounsToken.mint(voter, tokenId);

        address recipient1 = address(3);
        address recipient2 = address(4);
        vm.startPrank(manager);
        bytes32 recipientId1 = keccak256(abi.encodePacked(recipient1));
        bytes32 recipientId2 = keccak256(abi.encodePacked(recipient2));
        flow.addRecipient(recipientId1, recipient1, recipientMetadata);
        flow.addRecipient(recipientId2, recipient2, recipientMetadata);
        vm.stopPrank();

        // Step 3: Prepare vote data
        bytes32[] memory recipientIds = new bytes32[](2);
        uint32[] memory percentAllocations = new uint32[](2);
        uint256[] memory tokenIds = new uint256[](1);

        recipientIds[0] = recipientId1;
        recipientIds[1] = recipientId2;
        percentAllocations[0] = splitPercentage;
        percentAllocations[1] = 1e6 - splitPercentage;
        tokenIds[0] = tokenId;

        // Step 4: Cast votes
        vm.prank(voter);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        // Step 5: Verify vote allocations
        Flow.Allocation[] memory voteAllocations = getAllocationForTokenId(tokenId);

        // Check number of allocations
        assertEq(voteAllocations.length, 2);

        // Check first allocation
        assertEq(voteAllocations[0].recipientId, recipientId1);
        assertEq(voteAllocations[0].bps, splitPercentage);
        assertGt(voteAllocations[0].memberUnits, 0);

        // Check second allocation
        assertEq(voteAllocations[1].recipientId, recipientId2);
        assertEq(voteAllocations[1].bps, 1e6 - splitPercentage);
        assertGt(voteAllocations[1].memberUnits, 0);

        // Step 6: Compare member units based on split percentage
        if (splitPercentage > 5e5) {
            assertGt(voteAllocations[0].memberUnits, voteAllocations[1].memberUnits);
        } else if (splitPercentage < 5e5) {
            assertLt(voteAllocations[0].memberUnits, voteAllocations[1].memberUnits);
        } else {
            assertEq(voteAllocations[0].memberUnits, voteAllocations[1].memberUnits);
        }

        // Step 7: Ensure total member units are greater than zero
        uint256 totalMemberUnits = uint256(voteAllocations[0].memberUnits) + uint256(voteAllocations[1].memberUnits);
        assertGt(totalMemberUnits, 0);
    }

    function test__ClearVotesAllocations() public {
        address voter = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter, tokenId);

        address recipient1 = address(3);
        address recipient2 = address(4);
        vm.startPrank(manager);
        bytes32 recipientId1 = keccak256(abi.encodePacked(recipient1));
        bytes32 recipientId2 = keccak256(abi.encodePacked(recipient2));
        flow.addRecipient(recipientId1, recipient1, recipientMetadata);
        flow.addRecipient(recipientId2, recipient2, recipientMetadata);
        vm.stopPrank();

        bytes32[] memory recipientIds = new bytes32[](2);
        uint32[] memory percentAllocations = new uint32[](2);
        uint256[] memory tokenIds = new uint256[](1);

        recipientIds[0] = recipientId1;
        recipientIds[1] = recipientId2;
        percentAllocations[0] = 5e5; // 50%
        percentAllocations[1] = 5e5; // 50%
        tokenIds[0] = tokenId;

        vm.prank(voter);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        uint128 recipient1OriginalUnits = flow.bonusPool().getUnits(recipient1);
        uint128 recipient2OriginalUnits = flow.bonusPool().getUnits(recipient2);

        assertGt(recipient1OriginalUnits, 0);
        assertGt(recipient2OriginalUnits, 0);

        // Change vote to only recipient1
        bytes32[] memory newRecipientIds = new bytes32[](1);
        uint32[] memory newPercentAllocations = new uint32[](1);
        newRecipientIds[0] = recipientId1;
        newPercentAllocations[0] = 1e6; // 100%

        vm.prank(voter);
        flow.allocate(_prepTokens(tokenIds), newRecipientIds, newPercentAllocations);

        uint128 recipient1NewUnits = flow.bonusPool().getUnits(recipient1);
        uint128 recipient2NewUnits = flow.bonusPool().getUnits(recipient2);

        assertGt(recipient1NewUnits, recipient1OriginalUnits);
        assertEq(recipient2NewUnits, 10); // 10 units for each recipient in case there are no votes yet, everyone will split the bonus salary

        // Verify that the votes for the tokenId have been updated
        Flow.Allocation[] memory voteAllocations = getAllocationForTokenId(tokenId);
        assertEq(voteAllocations.length, 1);
        assertEq(voteAllocations[0].recipientId, recipientId1);
        assertEq(voteAllocations[0].bps, 1e6);
    }

    function test__FlowRecipientFlowRateChanges() public {
        address voter = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter, tokenId);

        address recipient1 = address(3);
        vm.startPrank(manager);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient1));
        flow.addRecipient(recipientId, recipient1, recipientMetadata);
        bytes32 flowRecipientId = keccak256(abi.encodePacked(voter));
        (, address flowRecipient) = flow.addFlowRecipient(
            flowRecipientId,
            recipientMetadata,
            manager,
            address(0),
            strategies
        );
        vm.stopPrank();

        bytes32[] memory recipientIds = new bytes32[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        recipientIds[0] = flowRecipientId; // Flow recipient
        percentAllocations[0] = 1e6; // 100%
        tokenIds[0] = tokenId;

        // // ensure small balance - need to be able to set flow rate
        _transferTestTokenToFlow(flowRecipient, 56 * 10 ** 18);

        vm.prank(voter);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        int96 flowRecipientTotalFlowRate = Flow(flowRecipient).getTotalFlowRate();
        assertGt(flowRecipientTotalFlowRate, 0);

        // Change vote to recipient1
        recipientIds[0] = recipientId;
        percentAllocations[0] = 1e6; // 100%

        vm.prank(voter);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        // Check that total bonus salary flow rate to the flow recipient is basically 0
        int96 newFlowRecipientTotalFlowRate = flow.bonusPool().getMemberFlowRate(flowRecipient);
        assertLt(newFlowRecipientTotalFlowRate, flow.bonusPool().getMemberFlowRate(recipient1) / 1e5);
    }

    function test__FlowRecipientFlowRateBufferAmount() public {
        address voter = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter, tokenId);

        address recipient1 = address(3);

        vm.startPrank(manager);
        bytes32 recipientId1 = keccak256(abi.encodePacked(recipient1));
        flow.addRecipient(recipientId1, recipient1, recipientMetadata);
        bytes32 flowRecipientId = keccak256(abi.encodePacked(voter));
        (, address flowRecipient) = flow.addFlowRecipient(
            flowRecipientId,
            recipientMetadata,
            manager,
            address(0),
            strategies
        );
        vm.stopPrank();

        int96 incoming = flow.getMemberTotalFlowRate(flowRecipient);

        // the total flow rate should be greater than 0 because flows are automatically started now
        int96 outgoing = Flow(flowRecipient).getTotalFlowRate();
        assertEq(outgoing, incoming, "Initial incoming and outgoing flow rates should match");

        bytes32[] memory recipientIds = new bytes32[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        recipientIds[0] = flowRecipientId; // Flow recipient
        percentAllocations[0] = 1e6; // 100%
        tokenIds[0] = tokenId;

        vm.prank(voter);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        int96 incomingFlowRate = flow.getMemberTotalFlowRate(flowRecipient);

        int96 outgoingFlowRate = Flow(flowRecipient).getTotalFlowRate();
        assertEq(outgoingFlowRate, incomingFlowRate, "After voting, incoming and outgoing flow rates should match");
    }

    function testClearVotesAllocationsForFlows() public {
        address voter = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter, tokenId);

        vm.startPrank(manager);
        bytes32 recipientId1 = keccak256(abi.encodePacked(address(3)));
        bytes32 recipientId2 = keccak256(abi.encodePacked(address(4)));
        (, address recipient1) = flow.addFlowRecipient(
            recipientId1,
            recipientMetadata,
            manager,
            address(0),
            strategies
        );
        (, address recipient2) = flow.addFlowRecipient(
            recipientId2,
            recipientMetadata,
            manager,
            address(0),
            strategies
        );
        vm.stopPrank();

        bytes32[] memory recipientIds = new bytes32[](2);
        uint32[] memory percentAllocations = new uint32[](2);
        uint256[] memory tokenIds = new uint256[](1);

        recipientIds[0] = recipientId1;
        recipientIds[1] = recipientId2;
        percentAllocations[0] = 5e5; // 50%
        percentAllocations[1] = 5e5; // 50%
        tokenIds[0] = tokenId;

        vm.prank(voter);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        uint128 recipient1OriginalUnits = flow.bonusPool().getUnits(recipient1);
        uint128 recipient2OriginalUnits = flow.bonusPool().getUnits(recipient2);

        assertGt(recipient1OriginalUnits, 0);
        assertGt(recipient2OriginalUnits, 0);

        // track flow rates
        int96 recipient1FlowRate = Flow(recipient1).getTotalFlowRate();
        int96 recipient2FlowRate = Flow(recipient2).getTotalFlowRate();

        // Change vote to only recipient1
        bytes32[] memory newRecipientIds = new bytes32[](1);
        uint32[] memory newPercentAllocations = new uint32[](1);
        newRecipientIds[0] = recipientId1;
        newPercentAllocations[0] = 1e6; // 100%

        vm.prank(voter);
        flow.allocate(_prepTokens(tokenIds), newRecipientIds, newPercentAllocations);

        uint128 recipient1NewUnits = flow.bonusPool().getUnits(recipient1);
        uint128 recipient2NewUnits = flow.bonusPool().getUnits(recipient2);

        assertGt(recipient1NewUnits, recipient1OriginalUnits);
        assertEq(recipient2NewUnits, 10); // 10 units for each recipient in case there are no votes yet, everyone will split the bonus salary

        // Verify that the votes for the tokenId have been updated
        Flow.Allocation[] memory voteAllocations = getAllocationForTokenId(tokenId);
        assertEq(voteAllocations.length, 1);
        assertEq(voteAllocations[0].recipientId, recipientId1);
        assertEq(voteAllocations[0].bps, 1e6);

        // check that recipient1 flow rate has gone up
        assertGt(Flow(recipient1).getTotalFlowRate(), recipient1FlowRate);

        // check that recipient2 flow rate has gone down
        assertLt(Flow(recipient2).getTotalFlowRate(), recipient2FlowRate);
    }

    function testtotalActiveAllocationWeightUpdatesCorrectly() public {
        // Initial setup
        uint256 tokenId1 = 1;
        uint256 tokenId2 = 2;
        address voter1 = address(0x123);
        address voter2 = address(0x456);

        address recipient = address(2);
        address recipient2 = address(1);
        vm.startPrank(manager);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));
        bytes32 recipientId2 = keccak256(abi.encodePacked(recipient2));
        flow.addRecipient(recipientId, recipient, recipientMetadata);
        flow.addRecipient(recipientId2, recipient2, recipientMetadata);
        vm.stopPrank();

        // Mint tokens to voters using nounsToken instead of erc721
        nounsToken.mint(voter1, tokenId1);
        nounsToken.mint(voter2, tokenId2);

        // Initial total active vote weight should be zero
        assertEq(flow.totalActiveAllocationWeight(), 0);

        // First voter casts votes
        bytes32[] memory recipientIds = new bytes32[](1);
        recipientIds[0] = recipientId;
        uint32[] memory percentAllocations = new uint32[](1);
        percentAllocations[0] = 1e6; // 100%
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId1;

        vm.prank(voter1);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        // After first vote, total active vote weight should increase by tokenVoteWeight
        assertEq(flow.totalActiveAllocationWeight(), tokenVoteWeight());

        // Same voter casts votes again, total active vote weight should not change
        vm.prank(voter1);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        assertEq(flow.totalActiveAllocationWeight(), tokenVoteWeight());

        // Second voter casts votes
        tokenIds[0] = tokenId2;
        vm.prank(voter2);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        // After second voter votes, total active vote weight should increase again
        assertEq(flow.totalActiveAllocationWeight(), tokenVoteWeight() * 2);

        // Change votes from recipient1 to recipient2 for voter1
        recipientIds[0] = recipientId2;
        tokenIds[0] = tokenId1;

        vm.prank(voter1);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        // Ensure total active vote weight remains unchanged after changing votes
        assertEq(flow.totalActiveAllocationWeight(), tokenVoteWeight() * 2);

        // Voter1 casts votes again, switching back to recipient1
        recipientIds[0] = recipientId;
        tokenIds[0] = tokenId1;

        vm.prank(voter1);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        // Ensure total active vote weight remains unchanged after switching votes again
        assertEq(flow.totalActiveAllocationWeight(), tokenVoteWeight() * 2);

        // Voter1 casts votes again, switching back to recipient2
        recipientIds[0] = recipientId2;

        vm.prank(voter1);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        // Ensure total active vote weight remains unchanged after another vote switch
        assertEq(flow.totalActiveAllocationWeight(), tokenVoteWeight() * 2);
    }
}
