// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { IAllocationStrategy } from "../../src/interfaces/IAllocationStrategy.sol";

/**
 * @title WitnessCacheHelper
 * @dev Shared test helper for building and caching allocation witnesses across strategies.
 */
abstract contract WitnessCacheHelper {
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
}
