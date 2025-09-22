// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FlowTypes } from "../storage/FlowStorage.sol";
import { IFlow } from "../interfaces/IFlow.sol";
import { FlowRates } from "./FlowRates.sol";
import { FlowPools } from "./FlowPools.sol";
import { IFlowEvents } from "../interfaces/IFlow.sol";
import { IAllocationStrategy } from "../interfaces/IAllocationStrategy.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

library FlowAllocations {
    using FlowRates for FlowTypes.Storage;
    using FlowPools for FlowTypes.Storage;
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Checks that the recipients and percentAllocations are valid
     * @param recipientIds The recipientIds of the grant recipients.
     * @param percentAllocations The basis points of the vote to be split with the recipients.
     */
    function validateAllocations(
        FlowTypes.Storage storage fs,
        bytes32[] calldata recipientIds,
        uint32[] calldata percentAllocations
    ) public view {
        _assertSortedUnique(recipientIds);

        // recipientIds & percentAllocations must be equal length
        if (recipientIds.length != percentAllocations.length) {
            revert IFlow.RECIPIENTS_ALLOCATIONS_MISMATCH(recipientIds.length, percentAllocations.length);
        }

        uint256 sum = 0;

        // ensure recipients are not 0 address and allocations are > 0
        for (uint256 i = 0; i < recipientIds.length; i++) {
            bytes32 recipientId = recipientIds[i];
            if (fs.recipients[recipientId].recipient == address(0)) revert IFlow.INVALID_RECIPIENT_ID();
            if (fs.recipients[recipientId].removed == true) revert IFlow.NOT_APPROVED_RECIPIENT();
            if (percentAllocations[i] == 0) revert IFlow.ALLOCATION_MUST_BE_POSITIVE();
            sum += percentAllocations[i];
        }

        if (sum != fs.PERCENTAGE_SCALE) revert IFlow.INVALID_BPS_SUM();
    }

    /**
     * @notice Multiplies an amount by a scaled percentage
     *  @param amount Amount to get `scaledPercentage` of
     *  @param scaledPercent Percent scaled by PERCENTAGE_SCALE
     *  @return scaledAmount Percent of `amount`.
     */
    function _scaleAmountByPercentage(
        FlowTypes.Storage storage fs,
        uint256 amount,
        uint256 scaledPercent
    ) public view returns (uint256) {
        return Math.mulDiv(amount, scaledPercent, fs.PERCENTAGE_SCALE);
    }

    // ========= Option C core: commitment + witness, delta updates (no per-recipient storage writes) =========
    /**
     * @dev Applies allocation deltas for a single (strategy, allocationKey).
     * - Verifies the witness against the stored commitment (order-independent).
     * - On first use for a key, migrates from legacy storage,
     * - using exact legacy memberUnits for deltas (no rounding drift).
     * - Computes new per-recipient units from strategy.currentWeight(key) and new BPS.
     * - Updates pool units by delta (one call per touched recipient).
     * - Updates totalActiveAllocationWeight:
     *   - if migrating from legacy storage, subtract previous sum-of-floors;
     *   - otherwise, subtract the previous exact weight (from the witness);
     *   - add the new strategy weight.
     * - Stores the new commitment.
     */
    function applyAllocationWithWitness(
        FlowTypes.Storage storage fs,
        EnumerableSet.AddressSet storage _childFlows,
        EnumerableSet.AddressSet storage _childFlowsToUpdateFlowRate,
        address strategy,
        uint256 allocationKey,
        bytes32[] memory prevRecipientIds,
        uint32[] memory prevBps,
        uint256 prevWeight, // weight used to compute previous units (from last commit)
        bytes32[] calldata newRecipientIds,
        uint32[] calldata newBps
    ) public returns (uint256 childFlowsToUpdate, bool shouldUpdateFlowRate) {
        uint256 scale = fs.PERCENTAGE_SCALE;
        uint256 newWeight = IAllocationStrategy(strategy).currentWeight(allocationKey); // on-chain source of truth

        // New inputs must be strictly sorted and unique for canonical hashing and linear merge
        _assertSortedUnique(newRecipientIds);

        // --- determine prior state: commitment or legacy migration ---
        bytes32 oldCommit = fs.allocCommit[strategy][allocationKey];
        FlowTypes.Allocation[] memory legacy = oldCommit == bytes32(0)
            ? fs.allocations[strategy][allocationKey]
            : new FlowTypes.Allocation[](0);
        bool migratingFromLegacy = (oldCommit == bytes32(0) && legacy.length > 0);
        bool isBrandNewKey = (oldCommit == bytes32(0) && legacy.length == 0);

        if (oldCommit != bytes32(0)) {
            // Verify the provided previous witness against stored commitment (canonical, order-independent).
            if (prevRecipientIds.length > 0) {
                _assertSortedUniqueMemory(prevRecipientIds);
            }
            if (_hashAllocCanonical(prevWeight, prevRecipientIds, prevBps) != oldCommit) {
                revert IFlow.INVALID_PREV_ALLOCATION();
            }
        }

        // --- assemble old & new unit pairs; compute sum-of-floors for quorum accounting ---
        _PairUnits[] memory oldPairs; // old side (units, bps for event)
        uint256 oldSumFloors;
        if (migratingFromLegacy) {
            (oldPairs, oldSumFloors) = _pairsUnitsFromLegacy(legacy); // exact legacy units + legacy sum-of-floors
        } else if (oldCommit != bytes32(0)) {
            // recompute from commit
            (oldPairs, oldSumFloors) = _pairsUnitsFromComputed(prevRecipientIds, prevBps, prevWeight, scale);
        } else {
            oldPairs = new _PairUnits[](0);
            oldSumFloors = 0; // truly new
        }
        // new units + new sum-of-floors (not stored)
        (_PairUnits[] memory newPairs, ) = _pairsUnitsFromComputedCalldata(newRecipientIds, newBps, newWeight, scale);

        // --- sorting for merge ---
        // Require witness arrays sorted/unique; sort only legacy-derived pairs.
        if (migratingFromLegacy) {
            _sortUnits(oldPairs);
        }

        // --- new-key behavior (mirrors legacy: when there were previously no allocations for this key) ---
        if (isBrandNewKey && newRecipientIds.length > 0) {
            childFlowsToUpdate = 10;
            fs.setChildrenAsNeedingUpdates(_childFlows, _childFlowsToUpdateFlowRate, address(0));
            if (fs.bonusPoolQuorumBps > 0) {
                shouldUpdateFlowRate = true;
            }
        }
        // weight changed => quorum-sensitive recompute (matches original logic)
        if (fs.bonusPoolQuorumBps > 0) {
            if (migratingFromLegacy) {
                if (oldSumFloors != newWeight) shouldUpdateFlowRate = true;
            } else if (oldCommit != bytes32(0)) {
                if (prevWeight != newWeight) shouldUpdateFlowRate = true;
            }
            // isBrandNewKey still handled above
        }

        // --- merge/deltas ---
        uint256 oldIndex = 0;
        uint256 newIndex = 0;
        while (oldIndex < oldPairs.length || newIndex < newPairs.length) {
            bytes32 recipientIdCurrent;
            uint128 oldUnits;
            uint128 newUnits;
            uint32 currentBps;

            if (
                newIndex >= newPairs.length ||
                (oldIndex < oldPairs.length && oldPairs[oldIndex].id < newPairs[newIndex].id)
            ) {
                recipientIdCurrent = oldPairs[oldIndex].id;
                oldUnits = oldPairs[oldIndex].units;
                newUnits = 0;
                currentBps = 0;
                unchecked {
                    ++oldIndex;
                }
            } else if (
                oldIndex >= oldPairs.length ||
                (newIndex < newPairs.length && newPairs[newIndex].id < oldPairs[oldIndex].id)
            ) {
                recipientIdCurrent = newPairs[newIndex].id;
                oldUnits = 0;
                newUnits = newPairs[newIndex].units;
                currentBps = newPairs[newIndex].bps;
                unchecked {
                    ++newIndex;
                }
            } else {
                recipientIdCurrent = oldPairs[oldIndex].id;
                oldUnits = oldPairs[oldIndex].units;
                newUnits = newPairs[newIndex].units;
                currentBps = newPairs[newIndex].bps;
                unchecked {
                    ++oldIndex;
                    ++newIndex;
                }
            }

            // Skip recipients that are invalid/removed now.
            FlowTypes.FlowRecipient storage recipient = fs.recipients[recipientIdCurrent];
            address recipientAddress = recipient.recipient;
            if (recipientAddress == address(0) || recipient.removed) {
                continue;
            }

            int256 delta = int256(uint256(newUnits)) - int256(uint256(oldUnits));
            if (delta == 0) {
                // Emit for visibility (parity with legacy behavior)
                if (currentBps > 0) {
                    emit IFlowEvents.AllocationSet(
                        recipientIdCurrent,
                        strategy,
                        allocationKey,
                        newUnits,
                        currentBps,
                        newWeight
                    );
                }
                continue;
            }

            // Snapshot before unit change (for child flows net increase calc)
            fs.maybeTakeFlowRateSnapshot(_childFlows, recipientAddress);

            uint128 current = fs.bonusPool.getUnits(recipientAddress);
            uint128 target;
            if (delta < 0) {
                uint256 dec = uint256(-delta);
                target = dec >= current ? 0 : current - uint128(dec);
            } else {
                uint256 sum = uint256(current) + uint256(delta);
                if (sum > type(uint128).max) revert IFlow.OVERFLOW();
                target = uint128(sum);
            }

            // Single pool write for this recipient
            fs.updateBonusMemberUnits(recipientAddress, target);

            // Queue child flow update if needed
            if (
                recipient.recipientType == FlowTypes.RecipientType.FlowContract &&
                !_childFlowsToUpdateFlowRate.contains(recipientAddress)
            ) {
                _childFlowsToUpdateFlowRate.add(recipientAddress);
                unchecked {
                    ++childFlowsToUpdate;
                }
            }

            // Emit event for recipients present in new set
            if (currentBps > 0) {
                emit IFlowEvents.AllocationSet(
                    recipientIdCurrent,
                    strategy,
                    allocationKey,
                    newUnits,
                    currentBps,
                    newWeight
                );
            }
        }

        // total active allocation weight delta:
        // - legacy -> commit migration: subtract old sum-of-floors
        // - subsequent updates (commit -> commit): subtract previous exact weight
        // - always add new strategy weight
        uint256 prevComponent = migratingFromLegacy ? oldSumFloors : (oldCommit != bytes32(0) ? prevWeight : 0);
        fs.totalActiveAllocationWeight = fs.totalActiveAllocationWeight - prevComponent + newWeight;

        // Store canonical commitment for the new state and emit commit-level event
        // Inputs are strictly sorted/unique in calldata; hash directly without sorting/copying
        bytes32 commit = keccak256(abi.encode(newWeight, newRecipientIds, newBps));
        fs.allocCommit[strategy][allocationKey] = commit;
        emit IFlowEvents.AllocationCommitted(strategy, allocationKey, commit, newWeight);
    }

    // ============ Internal helpers ============
    struct _PairBps {
        bytes32 id;
        uint32 bps;
    }

    struct _PairUnits {
        bytes32 id;
        uint128 units;
        uint32 bps; // kept for event emission
    }

    function _assertSortedUnique(bytes32[] calldata ids) internal pure {
        if (ids.length == 0) revert IFlow.TOO_FEW_RECIPIENTS();
        bytes32 prev = ids[0];
        for (uint256 i = 1; i < ids.length; ++i) {
            bytes32 cur = ids[i];
            if (cur <= prev) revert IFlow.NOT_SORTED_OR_DUPLICATE();
            prev = cur;
        }
    }

    function _assertSortedUniqueMemory(bytes32[] memory ids) internal pure {
        if (ids.length == 0) return; // empty witness allowed for brand-new keys
        bytes32 prev = ids[0];
        for (uint256 i = 1; i < ids.length; ++i) {
            bytes32 cur = ids[i];
            if (cur <= prev) revert IFlow.NOT_SORTED_OR_DUPLICATE();
            prev = cur;
        }
    }

    function _pairsBps(bytes32[] memory ids, uint32[] memory bps) internal pure returns (_PairBps[] memory pairs) {
        require(ids.length == bps.length, "ids/bps mismatch");
        pairs = new _PairBps[](ids.length);
        for (uint256 i; i < ids.length; ) {
            pairs[i] = _PairBps({ id: ids[i], bps: bps[i] });
            unchecked {
                ++i;
            }
        }
    }

    function _pairsUnitsFromComputed(
        bytes32[] memory ids,
        uint32[] memory bps,
        uint256 weight,
        uint256 scale
    ) internal pure returns (_PairUnits[] memory pairs, uint256 sumFloors) {
        require(ids.length == bps.length, "ids/bps mismatch");
        pairs = new _PairUnits[](ids.length);
        for (uint256 i; i < ids.length; ) {
            uint256 w = Math.mulDiv(weight, bps[i], scale);
            sumFloors += w;
            uint256 u = w / 1e15;
            if (u > type(uint128).max) revert IFlow.OVERFLOW();
            pairs[i] = _PairUnits({ id: ids[i], units: uint128(u), bps: bps[i] });
            unchecked {
                ++i;
            }
        }
    }

    function _pairsUnitsFromComputedCalldata(
        bytes32[] calldata ids,
        uint32[] calldata bps,
        uint256 weight,
        uint256 scale
    ) internal pure returns (_PairUnits[] memory pairs, uint256 sumFloors) {
        require(ids.length == bps.length, "ids/bps mismatch");
        pairs = new _PairUnits[](ids.length);
        for (uint256 i; i < ids.length; ++i) {
            uint256 w = Math.mulDiv(weight, bps[i], scale);
            sumFloors += w;
            uint256 u = w / 1e15;
            if (u > type(uint128).max) revert IFlow.OVERFLOW();
            pairs[i] = _PairUnits({ id: ids[i], units: uint128(u), bps: bps[i] });
        }
    }

    function _pairsUnitsFromLegacy(
        FlowTypes.Allocation[] memory legacy
    ) internal pure returns (_PairUnits[] memory pairs, uint256 sumFloors) {
        pairs = new _PairUnits[](legacy.length);
        for (uint256 i; i < legacy.length; ) {
            pairs[i] = _PairUnits({ id: legacy[i].recipientId, units: legacy[i].memberUnits, bps: legacy[i].bps });
            sumFloors += legacy[i].allocationWeight;
            unchecked {
                ++i;
            }
        }
    }

    function _sortUnits(_PairUnits[] memory arr) internal pure {
        if (arr.length < 2) return;
        _qsu(arr, int256(0), int256(arr.length - 1));
    }

    function _qsu(_PairUnits[] memory a, int256 lo, int256 hi) private pure {
        int256 i = lo;
        int256 j = hi;
        _PairUnits memory p = a[uint256(lo + (hi - lo) / 2)];
        while (i <= j) {
            while (a[uint256(i)].id < p.id) {
                unchecked {
                    ++i;
                }
            }
            while (a[uint256(j)].id > p.id) {
                unchecked {
                    --j;
                }
            }
            if (i <= j) {
                (_PairUnits memory ai, _PairUnits memory aj) = (a[uint256(i)], a[uint256(j)]);
                a[uint256(i)] = aj;
                a[uint256(j)] = ai;
                unchecked {
                    ++i;
                    --j;
                }
            }
        }
        if (lo < j) _qsu(a, lo, j);
        if (i < hi) _qsu(a, i, hi);
    }

    function _sortBps(_PairBps[] memory arr) internal pure {
        if (arr.length < 2) return;
        _qsb(arr, int256(0), int256(arr.length - 1));
    }

    function _qsb(_PairBps[] memory a, int256 lo, int256 hi) private pure {
        int256 i = lo;
        int256 j = hi;
        _PairBps memory p = a[uint256(lo + (hi - lo) / 2)];
        while (i <= j) {
            while (a[uint256(i)].id < p.id) {
                unchecked {
                    ++i;
                }
            }
            while (a[uint256(j)].id > p.id) {
                unchecked {
                    --j;
                }
            }
            if (i <= j) {
                (_PairBps memory ai, _PairBps memory aj) = (a[uint256(i)], a[uint256(j)]);
                a[uint256(i)] = aj;
                a[uint256(j)] = ai;
                unchecked {
                    ++i;
                    --j;
                }
            }
        }
        if (lo < j) _qsb(a, lo, j);
        if (i < hi) _qsb(a, i, hi);
    }

    function _hashAllocCanonical(
        uint256 weight,
        bytes32[] memory ids,
        uint32[] memory bps
    ) internal pure returns (bytes32) {
        if (ids.length != bps.length) revert IFlow.ARRAY_LENGTH_MISMATCH();
        // Inputs must already be sorted and unique in ascending order
        return keccak256(abi.encode(weight, ids, bps));
    }
}
