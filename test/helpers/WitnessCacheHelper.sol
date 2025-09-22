// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { IAllocationStrategy } from "../../src/interfaces/IAllocationStrategy.sol";
import { Test } from "forge-std/Test.sol";

/**
 * @title WitnessCacheHelper
 * @dev Shared test helper for building and caching allocation witnesses across strategies.
 */
// Minimal interface to call allocate on flow contracts
interface IFlowAllocate {
    function allocate(
        bytes[][] calldata allocationData,
        bytes[][] calldata prevAllocationWitnesses,
        bytes32[] calldata recipientIds,
        uint32[] calldata percentAllocations
    ) external;
}

abstract contract WitnessCacheHelper is Test {
    // =========================
    // Witness caching for tests
    // =========================

    struct PrevWitnessCacheItem {
        bool exists;
        uint256 prevWeight;
        bytes32[] recipientIds;
        uint32[] bps;
    }

    // strategy => allocationKey => cached previous allocation witness
    mapping(address => mapping(uint256 => PrevWitnessCacheItem)) internal _prevWitness;

    function _encodePrevWitness(address strategyAddr, uint256 allocationKey) internal view returns (bytes memory) {
        PrevWitnessCacheItem storage item = _prevWitness[strategyAddr][allocationKey];
        if (!item.exists) return "";
        return abi.encode(item.prevWeight, item.recipientIds, item.bps);
    }

    function _buildEmptyWitnesses(bytes[][] memory allocationData) internal pure returns (bytes[][] memory) {
        bytes[][] memory witnesses = new bytes[][](allocationData.length);
        for (uint256 i = 0; i < allocationData.length; i++) {
            witnesses[i] = new bytes[](allocationData[i].length);
            for (uint256 j = 0; j < allocationData[i].length; j++) {
                witnesses[i][j] = "";
            }
        }
        return witnesses;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Multi-strategy helpers (expects strategies array aligned with allocationData)
    // ─────────────────────────────────────────────────────────────────────────────

    function _buildWitnessesForStrategies(
        address allocator,
        bytes[][] memory allocationData,
        IAllocationStrategy[] storage strategies
    ) internal view returns (bytes[][] memory) {
        bytes[][] memory witnesses = new bytes[][](allocationData.length);
        for (uint256 i = 0; i < allocationData.length; i++) {
            IAllocationStrategy strategy_ = strategies[i];
            witnesses[i] = new bytes[](allocationData[i].length);
            for (uint256 j = 0; j < allocationData[i].length; j++) {
                uint256 key = IAllocationStrategy(address(strategy_)).allocationKey(allocator, allocationData[i][j]);
                witnesses[i][j] = _encodePrevWitness(address(strategy_), key);
            }
        }
        return witnesses;
    }

    // Sort ids and bps in tandem by ids asc
    function _sortAllocPairs(bytes32[] memory ids, uint32[] memory bps) internal pure {
        // If lengths mismatch or trivial length, skip sorting and let contract handle validation
        if (ids.length != bps.length || ids.length < 2) return;
        _qsortPairs(ids, bps, int256(0), int256(ids.length - 1));
    }

    function _qsortPairs(bytes32[] memory ids, uint32[] memory bps, int256 lo, int256 hi) private pure {
        int256 i = lo;
        int256 j = hi;
        bytes32 p = ids[uint256(lo + (hi - lo) / 2)];
        while (i <= j) {
            while (ids[uint256(i)] < p) i++;
            while (ids[uint256(j)] > p) j--;
            if (i <= j) {
                (ids[uint256(i)], ids[uint256(j)]) = (ids[uint256(j)], ids[uint256(i)]);
                (bps[uint256(i)], bps[uint256(j)]) = (bps[uint256(j)], bps[uint256(i)]);
                i++;
                j--;
            }
        }
        if (lo < j) _qsortPairs(ids, bps, lo, j);
        if (i < hi) _qsortPairs(ids, bps, i, hi);
    }

    function _updateWitnessCacheForStrategies(
        address allocator,
        bytes[][] memory allocationData,
        IAllocationStrategy[] storage strategies,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations
    ) internal {
        for (uint256 i = 0; i < allocationData.length; i++) {
            IAllocationStrategy strategy_ = strategies[i];
            address strategyAddr = address(strategy_);
            for (uint256 j = 0; j < allocationData[i].length; j++) {
                uint256 key = IAllocationStrategy(strategyAddr).allocationKey(allocator, allocationData[i][j]);
                uint256 weightUsed = IAllocationStrategy(strategyAddr).currentWeight(key);

                PrevWitnessCacheItem storage item = _prevWitness[strategyAddr][key];
                item.exists = true;
                item.prevWeight = weightUsed;
                item.recipientIds = recipientIds;
                item.bps = percentAllocations;
            }
        }
    }

    function _allocateWithWitnessForStrategies(
        address allocator,
        bytes[][] memory allocationData,
        IAllocationStrategy[] storage strategies,
        address flowAddr,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations
    ) internal {
        _sortAllocPairs(recipientIds, percentAllocations);
        bytes[][] memory witnesses = _buildWitnessesForStrategies(allocator, allocationData, strategies);
        vm.prank(allocator);
        IFlowAllocate(flowAddr).allocate(allocationData, witnesses, recipientIds, percentAllocations);
        _updateWitnessCacheForStrategies(allocator, allocationData, strategies, recipientIds, percentAllocations);
    }

    function _allocateWithWitnessForStrategiesExpectRevert(
        address allocator,
        bytes[][] memory allocationData,
        IAllocationStrategy[] storage strategies,
        address flowAddr,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations,
        bytes memory expectedRevert
    ) internal {
        _sortAllocPairs(recipientIds, percentAllocations);
        bytes[][] memory witnesses = _buildWitnessesForStrategies(allocator, allocationData, strategies);
        if (expectedRevert.length > 0) vm.expectRevert(expectedRevert);
        vm.prank(allocator);
        IFlowAllocate(flowAddr).allocate(allocationData, witnesses, recipientIds, percentAllocations);
        _updateWitnessCacheForStrategies(allocator, allocationData, strategies, recipientIds, percentAllocations);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Single-strategy helpers
    // ─────────────────────────────────────────────────────────────────────────────

    function _buildWitnessesForStrategy(
        address allocator,
        bytes[][] memory allocationData,
        address strategyAddr
    ) internal view returns (bytes[][] memory) {
        bytes[][] memory witnesses = new bytes[][](allocationData.length);
        for (uint256 i = 0; i < allocationData.length; i++) {
            witnesses[i] = new bytes[](allocationData[i].length);
            for (uint256 j = 0; j < allocationData[i].length; j++) {
                uint256 key = IAllocationStrategy(strategyAddr).allocationKey(allocator, allocationData[i][j]);
                witnesses[i][j] = _encodePrevWitness(strategyAddr, key);
            }
        }
        return witnesses;
    }

    function _updateWitnessCacheForStrategy(
        address allocator,
        bytes[][] memory allocationData,
        address strategyAddr,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations
    ) internal {
        for (uint256 i = 0; i < allocationData.length; i++) {
            for (uint256 j = 0; j < allocationData[i].length; j++) {
                uint256 key = IAllocationStrategy(strategyAddr).allocationKey(allocator, allocationData[i][j]);
                uint256 weightUsed = IAllocationStrategy(strategyAddr).currentWeight(key);

                PrevWitnessCacheItem storage item = _prevWitness[strategyAddr][key];
                item.exists = true;
                item.prevWeight = weightUsed;
                item.recipientIds = recipientIds;
                item.bps = percentAllocations;
            }
        }
    }

    function _allocateWithWitnessForStrategy(
        address allocator,
        bytes[][] memory allocationData,
        address strategyAddr,
        address flowAddr,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations
    ) internal {
        _sortAllocPairs(recipientIds, percentAllocations);
        bytes[][] memory witnesses = _buildWitnessesForStrategy(allocator, allocationData, strategyAddr);
        vm.prank(allocator);
        IFlowAllocate(flowAddr).allocate(allocationData, witnesses, recipientIds, percentAllocations);
        _updateWitnessCacheForStrategy(allocator, allocationData, strategyAddr, recipientIds, percentAllocations);
    }

    function _allocateWithWitnessForStrategyExpectRevert(
        address allocator,
        bytes[][] memory allocationData,
        address strategyAddr,
        address flowAddr,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations,
        bytes memory expectedRevert
    ) internal {
        _sortAllocPairs(recipientIds, percentAllocations);
        bytes[][] memory witnesses = _buildWitnessesForStrategy(allocator, allocationData, strategyAddr);
        if (expectedRevert.length > 0) vm.expectRevert(expectedRevert);
        vm.prank(allocator);
        IFlowAllocate(flowAddr).allocate(allocationData, witnesses, recipientIds, percentAllocations);
        _updateWitnessCacheForStrategy(allocator, allocationData, strategyAddr, recipientIds, percentAllocations);
    }
}
