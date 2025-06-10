// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { ERC721FlowTest } from "./ERC721Flow.t.sol";
import { IFlowEvents, IFlow } from "../../src/interfaces/IFlow.sol";
import { Flow } from "../../src/Flow.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { console } from "forge-std/console.sol";

contract VotingValidationTest is ERC721FlowTest {
    function setUp() public override {
        super.setUp();
    }

    function test__InvalidPercentAllocations() public {
        address voter1 = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter1, tokenId);

        address recipient = address(3);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));
        vm.prank(manager);
        flow.addRecipient(recipientId, recipient, recipientMetadata);

        bytes32[] memory recipientIds = new bytes32[](1);
        uint32[] memory percentAllocations = new uint32[](0);
        uint256[] memory tokenIds = new uint256[](1);

        recipientIds[0] = recipientId;
        tokenIds[0] = tokenId;

        vm.prank(voter1);
        bytes4 selector = bytes4(keccak256("RECIPIENTS_ALLOCATIONS_MISMATCH(uint256,uint256)"));

        vm.expectRevert(abi.encodeWithSelector(selector, 1, 0));
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        uint32[] memory percentAllocationsTwo = new uint32[](2);
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(selector, 1, 2));
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocationsTwo);

        // add new recipient
        address recipient2 = address(23);
        bytes32 recipientId2 = keccak256(abi.encodePacked(recipient2));
        vm.prank(manager);
        flow.addRecipient(recipientId2, recipient2, recipientMetadata);

        bytes32[] memory recipientIdsTwo = new bytes32[](2);
        recipientIdsTwo[0] = recipientId;
        recipientIdsTwo[1] = recipientId2;

        vm.expectRevert(IFlow.ALLOCATION_MUST_BE_POSITIVE.selector);
        vm.prank(voter1);
        flow.allocate(_prepTokens(tokenIds), recipientIdsTwo, percentAllocationsTwo);

        percentAllocationsTwo[0] = 1e6;
        percentAllocationsTwo[1] = 1e6;
        vm.prank(voter1);
        vm.expectRevert(IFlow.INVALID_BPS_SUM.selector);
        flow.allocate(_prepTokens(tokenIds), recipientIdsTwo, percentAllocationsTwo);
    }

    function test__InvalidRecipients() public {
        address voter1 = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter1, tokenId);

        address recipient = address(3);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));
        vm.prank(manager);
        flow.addRecipient(recipientId, recipient, recipientMetadata);

        bytes32[] memory recipientIds = new bytes32[](0);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        percentAllocations[0] = 1e6;
        tokenIds[0] = tokenId;

        vm.prank(voter1);
        vm.expectRevert(IFlow.TOO_FEW_RECIPIENTS.selector);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);

        address recipient2 = address(4);
        bytes32 recipientId2 = keccak256(abi.encodePacked(recipient2));
        vm.prank(manager);
        flow.addRecipient(recipientId2, recipient2, recipientMetadata);

        vm.prank(flow.owner());
        flow.removeRecipient(recipientId2);

        bytes32[] memory recipientIds2 = new bytes32[](1);
        recipientIds2[0] = recipientId2;

        vm.prank(voter1);
        vm.expectRevert(IFlow.NOT_APPROVED_RECIPIENT.selector);
        flow.allocate(_prepTokens(tokenIds), recipientIds2, percentAllocations);
    }

    function test__RecipientInvalidId() public {
        address voter1 = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter1, tokenId);

        address recipient = address(3);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));
        vm.prank(manager);
        flow.addRecipient(recipientId, recipient, recipientMetadata);

        bytes32[] memory recipientIds = new bytes32[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        percentAllocations[0] = 1e6;
        tokenIds[0] = tokenId;
        recipientIds[0] = bytes32(type(uint256).max); // Use an invalid recipient ID

        vm.prank(voter1);
        vm.expectRevert(IFlow.INVALID_RECIPIENT_ID.selector);
        flow.allocate(_prepTokens(tokenIds), recipientIds, percentAllocations);
    }
}
