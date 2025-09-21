// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { IAllocationStrategy } from "../../src/interfaces/IAllocationStrategy.sol";
import { Vm } from "forge-std/Vm.sol";

/**
 * @title WitnessCacheHelper
 * @dev Shared test helper for building and caching allocation witnesses across strategies.
 */
// Minimal interface to call allocateWithWitness on flow contracts
interface IAllocateWithWitness {
    function allocateWithWitness(
        bytes[][] calldata allocationData,
        bytes[][] calldata prevAllocationWitnesses,
        bytes32[] calldata recipientIds,
        uint32[] calldata percentAllocations
    ) external;
}

abstract contract WitnessCacheHelper {
    // hevm cheatcode handle
    Vm internal constant _vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
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
        bytes[][] memory witnesses = _buildWitnessesForStrategies(allocator, allocationData, strategies);
        _vm.prank(allocator);
        IAllocateWithWitness(flowAddr).allocateWithWitness(allocationData, witnesses, recipientIds, percentAllocations);
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
        bytes[][] memory witnesses = _buildWitnessesForStrategies(allocator, allocationData, strategies);
        if (expectedRevert.length > 0) _vm.expectRevert(expectedRevert);
        _vm.prank(allocator);
        IAllocateWithWitness(flowAddr).allocateWithWitness(allocationData, witnesses, recipientIds, percentAllocations);
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
        bytes[][] memory witnesses = _buildWitnessesForStrategy(allocator, allocationData, strategyAddr);
        _vm.prank(allocator);
        IAllocateWithWitness(flowAddr).allocateWithWitness(allocationData, witnesses, recipientIds, percentAllocations);
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
        bytes[][] memory witnesses = _buildWitnessesForStrategy(allocator, allocationData, strategyAddr);
        if (expectedRevert.length > 0) _vm.expectRevert(expectedRevert);
        _vm.prank(allocator);
        IAllocateWithWitness(flowAddr).allocateWithWitness(allocationData, witnesses, recipientIds, percentAllocations);
        _updateWitnessCacheForStrategy(allocator, allocationData, strategyAddr, recipientIds, percentAllocations);
    }
}
