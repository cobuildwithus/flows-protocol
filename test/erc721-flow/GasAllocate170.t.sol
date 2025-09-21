// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { ERC721FlowTest } from "./ERC721Flow.t.sol";

contract GasAllocate170Test is ERC721FlowTest {
    function testGasAllocateTo170Recipients() public {
        // Setup voter and token
        address voter = address(0xBEEF);
        uint256 tokenId = 170; // arbitrary token id
        nounsToken.mint(voter, tokenId);

        // Add 170 recipients under manager privileges
        vm.startPrank(manager);
        bytes32[] memory recipientIds = new bytes32[](170);
        for (uint256 i = 0; i < 170; i++) {
            address recipient = address(uint160(1000 + i));
            bytes32 rid = keccak256(abi.encodePacked(recipient));
            recipientIds[i] = rid;
            flow.addRecipient(rid, recipient, recipientMetadata);
        }
        vm.stopPrank();

        // Prepare 100% allocation split across 170 recipients
        uint32[] memory percentAllocations = new uint32[](170);
        uint32 baseShare = uint32(uint256(1_000_000) / 170);
        uint256 runningTotal = 0;
        for (uint256 i = 0; i < 169; i++) {
            percentAllocations[i] = baseShare;
            runningTotal += baseShare;
        }
        percentAllocations[169] = uint32(1_000_000 - runningTotal); // ensure sum is exactly 1e6

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.startPrank(voter);

        // First allocation (establishes previous allocations for the key)
        bytes[][] memory allocationData = _prepTokens(tokenIds);
        bytes[][] memory witnesses = _buildWitnessesForStrategies(voter, allocationData, strategies);
        flow.allocate(allocationData, witnesses, recipientIds, percentAllocations);
        // update witness cache so the second call has the correct previous witness
        _updateWitnessCacheForStrategies(voter, allocationData, strategies, recipientIds, percentAllocations);

        // Second allocation to the SAME key (tweak the split slightly)
        uint32[] memory percentAllocations2 = new uint32[](170);
        for (uint256 i = 0; i < 170; i++) percentAllocations2[i] = percentAllocations[i];
        if (percentAllocations2[0] > 0) {
            percentAllocations2[0] -= 1;
            percentAllocations2[1] += 1;
        }

        vm.pauseGasMetering();
        allocationData = _prepTokens(tokenIds);
        witnesses = _buildWitnessesForStrategies(voter, allocationData, strategies);
        vm.resumeGasMetering();

        uint256 gasBefore = gasleft();
        flow.allocate(allocationData, witnesses, recipientIds, percentAllocations2);
        uint256 witnessGasUsed = gasBefore - gasleft();

        vm.pauseGasMetering();
        vm.stopPrank();

        emit log_named_uint("Witness allocate(170 recipients) gas", witnessGasUsed);
    }
}
