// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FlowTypes } from "../storage/FlowStorage.sol";
import { IFlow } from "../interfaces/IFlow.sol";

import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library FlowRates {
    using SuperTokenV1Library for ISuperToken;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev how much extra buffer we add to the buffer amount
    uint256 constant EXTRA_BUFFER_PERCENT = 5; // 5%
    /// @dev how many child flows we can update per tx
    uint256 constant MAX_CHILD_UPDATES_PER_TX = 10;

    /**
     * @notice Calculates the bonus flow rate based on quorum and active votes
     * @param fs The storage of the Flow contract
     * @param _totalAllocationWeight The total token supply vote weight
     * @param _baselineFlowRate The baseline flow rate already calculated
     * @param _remainingFlowRate The remaining flow rate after manager reward deduction
     * @return bonusFlowRate The calculated bonus flow rate
     * @return leftoverFlowRate The leftover flow rate that is not used
     */
    function _calculateBonusFlowRate(
        FlowTypes.Storage storage fs,
        uint256 _totalAllocationWeight,
        int96 _baselineFlowRate,
        int96 _remainingFlowRate
    ) public view returns (int96 bonusFlowRate, int96 leftoverFlowRate) {
        // the max rate the bonus pool can have if it reaches full quorum
        int96 maxBonusFlowRate = _remainingFlowRate - _baselineFlowRate;
        // the quorum percentage
        uint256 quorumBps = fs.bonusPoolQuorumBps;

        // if quorum is 0 or total token supply vote weight is 0, return the max bonus flow rate
        // this is fine because when there are no votes the bonus pool is split evenly between recipients
        if (quorumBps == 0 || _totalAllocationWeight == 0) {
            return (maxBonusFlowRate, 0);
        }

        // how many votes have actually been cast
        uint256 totalActiveAllocationWeight = fs.totalActiveAllocationWeight;

        // how many votes are needed to reach quorum
        uint256 votesToReachQuorum = Math.mulDiv(
            _totalAllocationWeight,
            quorumBps,
            fs.PERCENTAGE_SCALE,
            Math.Rounding.Up
        );

        if (votesToReachQuorum == 0) {
            return (maxBonusFlowRate, 0);
        }

        // actual bonus flow rate is linearly proportional
        // to the total active vote weight / totalSupplyVoteWeight * quorumBps
        uint256 percentageOfQuorum = (totalActiveAllocationWeight * fs.PERCENTAGE_SCALE) / votesToReachQuorum;
        if (percentageOfQuorum > fs.PERCENTAGE_SCALE) {
            percentageOfQuorum = fs.PERCENTAGE_SCALE;
        }

        // actual bonus flow rate is linearly proportional
        // to the total active vote weight / totalSupplyVoteWeight * quorumBps
        int256 computedBonusFlowRate = SafeCast.toInt256(
            _scaleAmountByPercentage(fs, SafeCast.toUint256(maxBonusFlowRate), percentageOfQuorum)
        );

        if (computedBonusFlowRate > type(int96).max) revert IFlow.FLOW_RATE_TOO_HIGH();

        bonusFlowRate = int96(computedBonusFlowRate);

        leftoverFlowRate = maxBonusFlowRate - bonusFlowRate;
    }

    /**
     * @notice Calculates the flow rates for the flow contract
     * @param fs The storage of the Flow contract
     * @param _flowRate The desired flow rate for the flow contract
     * @param _totalAllocationWeight The total token supply vote weight
     * @return baselineFlowRate The baseline flow rate
     * @return bonusFlowRate The bonus flow rate
     * @return managerRewardFlowRate The manager reward pool flow rate
     */
    function calculateFlowRates(
        FlowTypes.Storage storage fs,
        int96 _flowRate,
        uint256 _totalAllocationWeight
    ) external view returns (int96 baselineFlowRate, int96 bonusFlowRate, int96 managerRewardFlowRate) {
        int256 managerRewardFlowRatePercent = SafeCast.toInt256(
            _scaleAmountByPercentage(fs, SafeCast.toUint256(_flowRate), fs.managerRewardPoolFlowRatePercent)
        );

        if (managerRewardFlowRatePercent > type(int96).max) revert IFlow.FLOW_RATE_TOO_HIGH();

        managerRewardFlowRate = int96(managerRewardFlowRatePercent);

        int96 remainingFlowRate = _flowRate - managerRewardFlowRate;

        int256 baselineFlowRate256 = SafeCast.toInt256(
            _scaleAmountByPercentage(fs, SafeCast.toUint256(remainingFlowRate), fs.baselinePoolFlowRatePercent)
        );

        if (baselineFlowRate256 > type(int96).max) revert IFlow.FLOW_RATE_TOO_HIGH();

        baselineFlowRate = int96(baselineFlowRate256);
        int96 leftoverFlowRate;

        (bonusFlowRate, leftoverFlowRate) = _calculateBonusFlowRate(
            fs,
            _totalAllocationWeight,
            baselineFlowRate,
            remainingFlowRate
        );

        // add the leftover flowrate to baseline
        baselineFlowRate += leftoverFlowRate;
    }

    /**
     * @notice Retrieves the actual flow rate for the Flow contract
     * @param fs The storage of the Flow contract
     * @param flowAddress The address of the flow contract
     * @return actualFlowRate The actual flow rate for the Flow contract
     */
    function getActualFlowRate(FlowTypes.Storage storage fs, address flowAddress) public view returns (int96) {
        return
            fs.superToken.getFlowRate(flowAddress, fs.managerRewardPool) +
            fs.superToken.getFlowDistributionFlowRate(flowAddress, fs.baselinePool) +
            fs.superToken.getFlowDistributionFlowRate(flowAddress, fs.bonusPool);
    }

    /**
     * @notice Retrieves the current flow rate to the manager reward pool
     * @param fs The storage of the Flow contract
     * @param flowAddress The address of the flow contract
     * @return flowRate The current flow rate to the manager reward pool
     */
    function getManagerRewardPoolFlowRate(
        FlowTypes.Storage storage fs,
        address flowAddress
    ) external view returns (int96 flowRate) {
        flowRate = fs.superToken.getFlowRate(flowAddress, fs.managerRewardPool);
    }

    /**
     * @notice Retrieves the flow rate for a specific member in the pool
     * @param memberAddr The address of the member
     * @return flowRate The flow rate for the member
     */
    function getMemberTotalFlowRate(
        FlowTypes.Storage storage fs,
        address memberAddr
    ) public view returns (int96 flowRate) {
        flowRate = fs.bonusPool.getMemberFlowRate(memberAddr) + fs.baselinePool.getMemberFlowRate(memberAddr);
    }

    /**
     * @notice Retrieves the claimable balance from both pools for a member address
     * @param fs The storage of the Flow contract
     * @param member The address of the member to check the claimable balance for
     * @return claimable The claimable balance from both pools
     */
    function getClaimableBalance(FlowTypes.Storage storage fs, address member) external view returns (uint256) {
        (int256 baselineClaimable, ) = fs.baselinePool.getClaimableNow(member);
        (int256 bonusClaimable, ) = fs.bonusPool.getClaimableNow(member);

        return uint256(baselineClaimable) + uint256(bonusClaimable);
    }

    /**
     * @notice Retrieves the total member units for a specific member across both pools
     * @param fs The storage of the Flow contract
     * @param memberAddr The address of the member
     * @return totalUnits The total units for the member
     */
    function getTotalMemberUnits(
        FlowTypes.Storage storage fs,
        address memberAddr
    ) external view returns (uint256 totalUnits) {
        totalUnits = fs.bonusPool.getUnits(memberAddr) + fs.baselinePool.getUnits(memberAddr);
    }

    /**
     * @notice Consumes the snapshot of the child flow rate
     * @param child The address of the child flow contract
     * @return before The previous flow rate of the child flow contract
     */
    function consumeFlowRateSnapshot(FlowTypes.Storage storage fs, address child) public returns (int96 before) {
        if (fs.rateSnapshotTaken[child]) {
            before = fs.oldChildFlowRate[child];
            clearFlowRateSnapshot(fs, child);
        } else {
            // Fallback – shouldn't happen but keeps math correct
            before = getMemberTotalFlowRate(fs, child);
        }
    }

    /**
     * @notice Clears the snapshot of the child flow rate
     * @param child The address of the child flow contract
     */
    function clearFlowRateSnapshot(FlowTypes.Storage storage fs, address child) public {
        delete fs.oldChildFlowRate[child];
        delete fs.rateSnapshotTaken[child];
    }

    /**
     * @notice Gets the net flow rate for the contract
     * @dev This function is used to get the net flow rate for the contract
     * @return The net flow rate
     */
    function getNetFlowRate(FlowTypes.Storage storage fs, address flowAddress) public view returns (int96) {
        return fs.superToken.getNetFlowRate(flowAddress);
    }

    /**
     * @notice Retrieves the maximum flow rate for the Flow contract
     * @param fs The storage of the Flow contract
     * @return maxFlowRate The maximum flow rate for the Flow contract
     */
    function getMaxSafeFlowRate(
        FlowTypes.Storage storage fs,
        address flowAddress
    ) public view returns (int96 maxFlowRate) {
        // Net = incoming - outgoing
        // Net + outgoing (getActualFlowRate) = incoming
        int96 netFlow = getNetFlowRate(fs, flowAddress);
        int96 outFlow = getActualFlowRate(fs, flowAddress);
        int96 inFlow = netFlow + outFlow;

        // If there is no incoming flow, the safe rate is zero.
        if (inFlow <= 0) return 0;

        // Cap the outflow to `outflowCapPct` of the incoming flow (scaled by `PERCENTAGE_SCALE`).
        uint256 capped = _scaleAmountByPercentage(fs, SafeCast.toUint256(inFlow), fs.outflowCapPct);
        return SafeCast.toInt96(SafeCast.toInt256(capped));
    }

    /**
     * @notice Gets the required buffer amount for a given flow rate
     * @param amount The flow rate to get the required buffer amount for
     * @return The required buffer amount
     */
    function getRequiredBufferAmount(
        FlowTypes.Storage storage fs,
        int96 amount,
        uint256 multiplier
    ) public view returns (uint256) {
        if (amount <= 0) revert IFlow.NOT_AN_INCREASE();

        uint256 newBuf = fs.superToken.getBufferAmountByFlowRate(amount);

        return Math.mulDiv(newBuf, multiplier * (100 + EXTRA_BUFFER_PERCENT), 100, Math.Rounding.Up);
    }

    /**
     * @notice Raise the outflow to `desiredRate`, pulling only the incremental buffer.
     * @param amount  New outflow to add to the current flow rate
     */
    function increaseFlowRate(
        FlowTypes.Storage storage fs,
        address flowAddress,
        int96 amount,
        uint256 multiplier
    ) public view returns (uint256 toPull, int96 oldRate, int96 newRate, int96 delta) {
        oldRate = getActualFlowRate(fs, flowAddress);
        int96 cap = getMaxSafeFlowRate(fs, flowAddress);

        newRate = oldRate + amount;

        // don't fail here, just cap it
        if (newRate > cap) newRate = cap;

        delta = newRate - oldRate;

        // If there is no real increase (delta <= 0) we can safely
        // return early without attempting to pull additional buffer.
        // This avoids the NOT_AN_INCREASE revert in
        // `getRequiredBufferAmount`
        if (delta <= 0) {
            return (0, oldRate, newRate, delta);
        }

        toPull = getRequiredBufferAmount(fs, delta, multiplier);
    }

    /**
     * @notice Takes a snapshot of the child flow rate
     * @param child The address of the child flow contract
     */
    function takeFlowRateSnapshot(FlowTypes.Storage storage fs, address child) public {
        if (!fs.rateSnapshotTaken[child]) {
            fs.oldChildFlowRate[child] = getMemberTotalFlowRate(fs, child);
            fs.rateSnapshotTaken[child] = true;
        }
    }

    /**
     * @notice Sets the flow buffer multiplier
     * @param _bufferMultiplier The new flow buffer multiplier
     * @dev Only callable by the owner or manager of the contract
     */
    function setDefaultBufferMultiplier(
        FlowTypes.Storage storage fs,
        uint256 _bufferMultiplier
    ) public returns (uint256 oldBufferMultiplier) {
        uint256 saneUpperBound = 20;
        if (_bufferMultiplier < 1 || _bufferMultiplier > saneUpperBound) revert IFlow.INVALID_BUFFER_MULTIPLIER();

        oldBufferMultiplier = fs.defaultBufferMultiplier;
        fs.defaultBufferMultiplier = _bufferMultiplier;
    }

    /**
     * @notice Checks if the flow rate is too high
     * @param fs The storage of the Flow contract
     * @param flowAddress The address of the flow contract
     * @return True if the flow rate is too high, false otherwise
     */
    function isFlowRateTooHigh(FlowTypes.Storage storage fs, address flowAddress) public view returns (bool) {
        return getActualFlowRate(fs, flowAddress) > getMaxSafeFlowRate(fs, flowAddress);
    }

    /**
     * @notice Sets the flow rate for a child Flow contract
     * @param fs The storage of the Flow contract
     * @param childAddress The address of the child Flow contract
     * @param _childFlows The set of child Flow contracts
     * @param _childFlowsToUpdateFlowRate The set of child Flow contracts to update the flow rate for
     */
    function setChildFlowRate(
        FlowTypes.Storage storage fs,
        address childAddress,
        address flowAddress,
        EnumerableSet.AddressSet storage _childFlows,
        EnumerableSet.AddressSet storage _childFlowsToUpdateFlowRate
    ) public {
        if (!_childFlows.contains(childAddress)) revert IFlow.NOT_A_VALID_CHILD_FLOW();

        _childFlowsToUpdateFlowRate.remove(childAddress);

        int96 previousRate = consumeFlowRateSnapshot(fs, childAddress);
        int96 newRate = getMemberTotalFlowRate(fs, childAddress);
        int96 netIncrease = newRate - previousRate;
        bool isTooHigh = IFlow(childAddress).isFlowRateTooHigh();

        // If we aren't increasing:
        if (netIncrease <= 0 || isTooHigh) {
            // act only when lowering the rate or when the child is over-cap
            if (netIncrease < 0 || isTooHigh) {
                bool successful;
                try IFlow(childAddress).decreaseFlowRate() {
                    successful = true;
                    takeFlowRateSnapshot(fs, childAddress);
                } catch {
                    successful = false;
                }
                if (!successful) {
                    _reAddChildFlowToUpdate(fs, _childFlowsToUpdateFlowRate, childAddress, previousRate);
                }
            }
            return; // nothing to raise
        }

        // get the current flow rate out of the child
        int96 childFlowRateBefore = IFlow(childAddress).getActualFlowRate();
        int96 headroom = IFlow(childAddress).getMaxSafeFlowRate() - childFlowRateBefore;

        if (headroom <= 0) {
            // nothing to do;
            return;
        }

        // cant increase above the cap
        if (netIncrease > headroom) netIncrease = headroom;

        // after clamping
        if (netIncrease <= 0) {
            // nothing to do;
            return;
        }

        uint256 approvalAmount = IFlow(childAddress).getRequiredBufferAmount(netIncrease);

        // ensure the parent has enough balance to cover the safe approval amount
        bool insufficientBalance = fs.superToken.balanceOf(flowAddress) < approvalAmount;

        if (insufficientBalance) {
            // leave child in the queue, skip for now
            _reAddChildFlowToUpdate(fs, _childFlowsToUpdateFlowRate, childAddress, previousRate);
            return;
        }

        fs.superToken.approve(childAddress, 0);
        bool ok = true;
        fs.superToken.approve(childAddress, approvalAmount);

        try IFlow(childAddress).increaseFlowRate(netIncrease) {
            ok = true;
        } catch {
            ok = false;
        }

        // reset approval
        fs.superToken.approve(childAddress, 0);

        // get the new flow rate increase
        int96 actualIncrease = IFlow(childAddress).getActualFlowRate() - childFlowRateBefore;
        bool closeEnough = _withinTolerance(netIncrease, actualIncrease);

        // tolerate small rounding differences
        if (!closeEnough) {
            ok = false;
        }

        if (!ok) {
            _reAddChildFlowToUpdate(fs, _childFlowsToUpdateFlowRate, childAddress, previousRate + actualIncrease);
        }
    }

    /**
     * @notice Returns true when `actual` is within the allowed rounding band of `expected`.
     * @param expected The expected flow rate
     * @param actual The actual flow rate
     * @return True if the actual flow rate is within the allowed rounding band of the expected flow rate, false otherwise
     */
    function _withinTolerance(int96 expected, int96 actual) public pure returns (bool) {
        if (expected == actual) return true; // fast path
        // if the flow rate was actually lowered, we can tolerate it
        if (actual < 0) return true;

        uint256 exp = SafeCast.toUint256(expected);
        uint256 act = SafeCast.toUint256(actual);

        // absolute difference
        uint256 diff = exp > act ? exp - act : act - exp;

        // Allowed band: 0.10 % of expected, but never less than 1 wei/sec.
        //                ─────┬─────
        //                     │  Single constant
        //                     ▼
        uint256 allowed = exp / 1000 + 1; // 1 / 1000  = 0.10 %

        // we can tolerate a small amount of rounding error
        uint256 minDiff = 1e3;
        bool isBelowMinDiff = diff < minDiff;

        // if the difference is within the allowed band or below the minimum difference, we can tolerate it
        return diff <= allowed || isBelowMinDiff;
    }

    /**
     * @notice Re-adds a child flow to the update flow rate set
     * @param fs The storage of the Flow contract
     * @param _childFlowsToUpdateFlowRate The set of child Flow contracts to update the flow rate for
     * @param childAddress The address of the child flow contract
     * @param previousRate The previous flow rate of the child flow contract
     */
    function _reAddChildFlowToUpdate(
        FlowTypes.Storage storage fs,
        EnumerableSet.AddressSet storage _childFlowsToUpdateFlowRate,
        address childAddress,
        int96 previousRate
    ) public {
        if (!fs.rateSnapshotTaken[childAddress]) {
            _childFlowsToUpdateFlowRate.add(childAddress);
            fs.oldChildFlowRate[childAddress] = previousRate;
            fs.rateSnapshotTaken[childAddress] = true;
        }
    }

    /**
     * @notice Gets the buffer multiplier
     * @param fs The storage of the Flow contract
     * @param _childFlows The set of child Flow contracts
     * @dev This function is used to get the buffer multiplier
     * @return The buffer multiplier
     */
    function getBufferMultiplier(
        FlowTypes.Storage storage fs,
        EnumerableSet.AddressSet storage _childFlows
    ) public view returns (uint256) {
        // If no child flows yet, use default multiplier 2; otherwise use configurable value.
        return _childFlows.length() == 0 ? 2 : fs.defaultBufferMultiplier;
    }

    /**
     * @notice Takes a snapshot of the child flow rate
     * @param fs The storage of the Flow contract
     * @param _childFlows The set of child Flow contracts
     * @param child The address of the child flow contract
     */
    function maybeTakeFlowRateSnapshot(
        FlowTypes.Storage storage fs,
        EnumerableSet.AddressSet storage _childFlows,
        address child
    ) public {
        if (_childFlows.contains(child) && !fs.rateSnapshotTaken[child]) {
            takeFlowRateSnapshot(fs, child);
        }
    }

    /**
     * @notice Sets all the child flow rates
     * @param fs The storage of the Flow contract
     * @param _childFlows The set of child Flow contracts
     * @param _childFlowsToUpdateFlowRate The set of child Flow contracts to update the flow rate for
     * @param ignoredAddress The address of the child flow to ignore. Useful when adding a new flow recipient
     * @dev Called when total member units change (new flow added, flow removed, new vote added)
     */
    function setChildrenAsNeedingUpdates(
        FlowTypes.Storage storage fs,
        EnumerableSet.AddressSet storage _childFlows,
        EnumerableSet.AddressSet storage _childFlowsToUpdateFlowRate,
        address ignoredAddress
    ) public {
        // warning - values() copies entire array into memory, could run out of gas for huge arrays
        // must keep child flows below ~500 per o1 estimates
        uint256 len = _childFlows.length();

        for (uint256 i = 0; i < len; i++) {
            address child = _childFlows.at(i);
            if (child == ignoredAddress) continue;

            maybeTakeFlowRateSnapshot(fs, _childFlows, child);

            _childFlowsToUpdateFlowRate.add(child);
        }
    }

    /**
     * @notice Internal function to work on the child flows that need their flow rate updated
     * @param fs The storage of the Flow contract
     * @param _childFlowsToUpdateFlowRate The set of child Flow contracts to update the flow rate for
     * @param updateCount The number of child flows to update
     */
    function workOnChildFlowsToUpdate(
        FlowTypes.Storage storage fs,
        EnumerableSet.AddressSet storage _childFlowsToUpdateFlowRate,
        EnumerableSet.AddressSet storage _childFlows,
        address flowAddress,
        uint256 updateCount
    ) public {
        uint256 limit = _childFlowsToUpdateFlowRate.length();
        if (limit > updateCount) limit = updateCount;
        if (limit > MAX_CHILD_UPDATES_PER_TX) limit = MAX_CHILD_UPDATES_PER_TX;

        address[] memory batch = new address[](limit);
        for (uint256 i; i < limit; ++i) {
            batch[i] = _childFlowsToUpdateFlowRate.at(i);
        }

        for (uint256 i; i < limit; ++i) {
            setChildFlowRate(fs, batch[i], flowAddress, _childFlows, _childFlowsToUpdateFlowRate);
        }
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
}
