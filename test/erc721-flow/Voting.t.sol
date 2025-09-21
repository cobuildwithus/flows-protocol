// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { ERC721FlowTest } from "./ERC721Flow.t.sol";
import { IFlowEvents, IFlow } from "../../src/interfaces/IFlow.sol";
import { Flow } from "../../src/Flow.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { console } from "forge-std/console.sol";
import { RewardPool } from "../../src/token-issuance/RewardPool.sol";

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

        allocateTokensWithWitnessHelper(voter1, tokenIds, recipientIds, percentAllocations);

        // get current member units of the pool
        uint128 currentUnits = flow.bonusPool().getUnits(recipient);

        assertGt(currentUnits, 0);

        recipientIds[0] = recipientId2;

        allocateTokensWithWitnessHelper(voter1, tokenIds, recipientIds, percentAllocations);

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

        allocateTokensWithWitnessHelper(voter2, tokenIds2, recipientIds, percentAllocations);

        // get current member units of the pool
        uint128 originalUnits = flow.bonusPool().getUnits(recipient);

        assertGt(originalUnits, 0);

        allocateTokensWithWitnessHelper(voter1, tokenIds, recipientIds, percentAllocations);

        uint128 secondVoteUnits = flow.bonusPool().getUnits(recipient);

        assertGt(secondVoteUnits, originalUnits);

        bytes32[] memory newRecipientIds = new bytes32[](1);
        newRecipientIds[0] = recipientId2;

        allocateTokensWithWitnessHelper(voter1, tokenIds, newRecipientIds, percentAllocations);

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
        allocateTokensWithWitnessHelper(voter, tokenIds, recipientIds, percentAllocations);
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

        allocateTokensWithWitnessHelper(voter, tokenIds, recipientIds, percentAllocations);

        uint128 recipient1OriginalUnits = flow.bonusPool().getUnits(recipient1);
        uint128 recipient2OriginalUnits = flow.bonusPool().getUnits(recipient2);

        assertGt(recipient1OriginalUnits, 0);
        assertGt(recipient2OriginalUnits, 0);

        // Change vote to only recipient1
        bytes32[] memory newRecipientIds = new bytes32[](1);
        uint32[] memory newPercentAllocations = new uint32[](1);
        newRecipientIds[0] = recipientId1;
        newPercentAllocations[0] = 1e6; // 100%

        allocateTokensWithWitnessHelper(voter, tokenIds, newRecipientIds, newPercentAllocations);

        uint128 recipient1NewUnits = flow.bonusPool().getUnits(recipient1);
        uint128 recipient2NewUnits = flow.bonusPool().getUnits(recipient2);

        assertGt(recipient1NewUnits, recipient1OriginalUnits);
        assertEq(recipient2NewUnits, 10); // 10 units for each recipient in case there are no votes yet, everyone will split the bonus salary
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

        allocateTokensWithWitnessHelper(voter, tokenIds, recipientIds, percentAllocations);

        int96 flowRecipientTotalFlowRate = Flow(flowRecipient).getTotalFlowRate();
        assertGt(flowRecipientTotalFlowRate, 0);

        // Change vote to recipient1
        recipientIds[0] = recipientId;
        percentAllocations[0] = 1e6; // 100%

        allocateTokensWithWitnessHelper(voter, tokenIds, recipientIds, percentAllocations);

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

        Flow(flowRecipient).setManagerRewardFlowRatePercent(0);
        vm.stopPrank();

        int96 incoming = flow.getMemberTotalFlowRate(flowRecipient);

        // the total flow rate should be greater than 0 because flows are automatically started now
        int96 outgoing = Flow(flowRecipient).getTotalFlowRate();
        assertEq(outgoing, (incoming * 999) / 1000, "Initial incoming and outgoing flow rates should match");

        bytes32[] memory recipientIds = new bytes32[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        recipientIds[0] = flowRecipientId; // Flow recipient
        percentAllocations[0] = 1e6; // 100%
        tokenIds[0] = tokenId;

        allocateTokensWithWitnessHelper(voter, tokenIds, recipientIds, percentAllocations);

        int96 incomingFlowRate = flow.getMemberTotalFlowRate(flowRecipient);

        int96 outgoingFlowRate = Flow(flowRecipient).getTotalFlowRate();

        console.log("incomingFlowRate", incomingFlowRate);
        console.log("outgoingFlowRate", outgoingFlowRate);

        assertEq(
            outgoingFlowRate,
            (incomingFlowRate * 999) / 1000, //1% buffer
            "After voting, incoming and outgoing flow rates should match"
        );
    }

    function testClearVotesAllocationsForFlows() public {
        // Setup: Create a voter and mint them a token
        address voter = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter, tokenId);

        vm.prank(manager);
        flow.setBaselineFlowRatePercent(0);

        // Setup: Create two flow recipients that can receive votes
        vm.startPrank(manager);
        bytes32 recipientId1 = keccak256(abi.encodePacked(address(3)));
        bytes32 recipientId2 = keccak256(abi.encodePacked(address(4)));
        (, address recipient1) = flow.addFlowRecipient(recipientId1, recipientMetadata, manager, manager, strategies);

        assertEq(flow.childFlowRatesOutOfSync(), 0);

        (, address recipient2) = flow.addFlowRecipient(recipientId2, recipientMetadata, manager, manager, strategies);
        vm.stopPrank();

        // Setup: Prepare vote allocation arrays for initial vote (50/50 split)
        bytes32[] memory recipientIds = new bytes32[](2);
        uint32[] memory percentAllocations = new uint32[](2);
        uint256[] memory tokenIds = new uint256[](1);

        recipientIds[0] = recipientId1;
        recipientIds[1] = recipientId2;
        percentAllocations[0] = 5e5; // 50%
        percentAllocations[1] = 5e5; // 50%
        tokenIds[0] = tokenId;

        // Initial vote: Split allocation 50/50 between two recipients
        allocateTokensWithWitnessHelper(voter, tokenIds, recipientIds, percentAllocations);

        // Record initial state: Get bonus pool units for both recipients after initial vote
        uint128 recipient1OriginalUnits = flow.bonusPool().getUnits(recipient1);
        uint128 recipient2OriginalUnits = flow.bonusPool().getUnits(recipient2);

        assertEq(flow.baselinePool().getUnits(recipient1), flow.baselinePool().getUnits(recipient2));

        // Verify both recipients received units from the initial vote
        assertGt(recipient1OriginalUnits, 0);
        assertGt(recipient2OriginalUnits, 0);
        assertEq(recipient1OriginalUnits, recipient2OriginalUnits);
        assertEq(flow.childFlowRatesOutOfSync(), 0);

        // Record initial flow rates to track changes after vote update
        int96 recipient1FlowRate = Flow(recipient1).getTotalFlowRate();
        int96 recipient2FlowRate = Flow(recipient2).getTotalFlowRate();

        assertEq(recipient1FlowRate, recipient2FlowRate);

        // Change vote: Update allocation to give 100% to recipient1 only
        bytes32[] memory newRecipientIds = new bytes32[](1);
        uint32[] memory newPercentAllocations = new uint32[](1);
        newRecipientIds[0] = recipientId1;
        newPercentAllocations[0] = 1e6; // 100%

        allocateTokensWithWitnessHelper(voter, tokenIds, newRecipientIds, newPercentAllocations);

        // Verify state after vote change: Get updated bonus pool units
        uint128 recipient1NewUnits = flow.bonusPool().getUnits(recipient1);
        uint128 recipient2NewUnits = flow.bonusPool().getUnits(recipient2);
        // Recipient1 should have more units now (got all the vote allocation)
        assertGt(
            recipient1NewUnits,
            recipient1OriginalUnits,
            "recipient1 should have more units after receiving 100% vote"
        );
        // Recipient2 should have minimum units (10) since they lost all vote allocation
        // but still get baseline units to participate in bonus pool distribution
        assertEq(recipient2NewUnits, 10, "recipient2 should have minimum units (10) after losing vote allocation");

        // Verify flow rate changes: recipient1 should receive more flow
        assertGt(
            Flow(recipient1).getTotalFlowRate(),
            recipient1FlowRate,
            "recipient1 flow rate should increase after receiving 100% vote"
        );

        // Verify flow rate changes: recipient2 should receive less flow
        assertLt(
            Flow(recipient2).getTotalFlowRate(),
            recipient2FlowRate,
            "recipient2 flow rate should decrease after losing vote allocation"
        );
    }

    function test__TotalActiveAllocationWeightUpdatesCorrectly() public {
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

        allocateTokensWithWitnessHelper(voter1, tokenIds, recipientIds, percentAllocations);

        // After first vote, total active vote weight should increase by tokenVoteWeight
        assertEq(flow.totalActiveAllocationWeight(), tokenVoteWeight());

        // Same voter casts votes again, total active vote weight should not change
        allocateTokensWithWitnessHelper(voter1, tokenIds, recipientIds, percentAllocations);

        assertEq(flow.totalActiveAllocationWeight(), tokenVoteWeight());

        // Second voter casts votes
        tokenIds[0] = tokenId2;
        allocateTokensWithWitnessHelper(voter2, tokenIds, recipientIds, percentAllocations);

        // After second voter votes, total active vote weight should increase again
        assertEq(flow.totalActiveAllocationWeight(), tokenVoteWeight() * 2);

        // Change votes from recipient1 to recipient2 for voter1
        recipientIds[0] = recipientId2;
        tokenIds[0] = tokenId1;

        allocateTokensWithWitnessHelper(voter1, tokenIds, recipientIds, percentAllocations);

        // Ensure total active vote weight remains unchanged after changing votes
        assertEq(flow.totalActiveAllocationWeight(), tokenVoteWeight() * 2);

        // Voter1 casts votes again, switching back to recipient1
        recipientIds[0] = recipientId;
        tokenIds[0] = tokenId1;

        allocateTokensWithWitnessHelper(voter1, tokenIds, recipientIds, percentAllocations);

        // Ensure total active vote weight remains unchanged after switching votes again
        assertEq(flow.totalActiveAllocationWeight(), tokenVoteWeight() * 2);

        // Voter1 casts votes again, switching back to recipient2
        recipientIds[0] = recipientId2;

        allocateTokensWithWitnessHelper(voter1, tokenIds, recipientIds, percentAllocations);

        // Ensure total active vote weight remains unchanged after another vote switch
        assertEq(flow.totalActiveAllocationWeight(), tokenVoteWeight() * 2);
    }
}
