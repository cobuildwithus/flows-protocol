// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FlowTypes } from "../storage/FlowStorage.sol";
import { IFlow } from "../interfaces/IFlow.sol";
import { IRewardPool } from "../interfaces/IRewardPool.sol";

import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

library FlowRates {
    using SuperTokenV1Library for ISuperToken;

    /**
     * @notice Calculates the bonus flow rate based on quorum and active votes
     * @param fs The storage of the Flow contract
     * @param _flowRate The desired total flow rate for the flow contract
     * @param _percentageScale The percentage scale used for calculations
     * @param _totalAllocationWeight The total token supply vote weight
     * @param _baselineFlowRate The baseline flow rate already calculated
     * @param _remainingFlowRate The remaining flow rate after manager reward deduction
     * @return bonusFlowRate The calculated bonus flow rate
     * @return leftoverFlowRate The leftover flow rate that is not used
     */
    function _calculateBonusFlowRate(
        FlowTypes.Storage storage fs,
        int96 _flowRate,
        uint256 _percentageScale,
        uint256 _totalAllocationWeight,
        int96 _baselineFlowRate,
        int96 _remainingFlowRate
    ) public returns (int96 bonusFlowRate, int96 leftoverFlowRate) {
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
        uint256 votesToReachQuorum = _scaleAmountByPercentage(_totalAllocationWeight, quorumBps, _percentageScale);

        if (votesToReachQuorum == 0) {
            return (maxBonusFlowRate, 0);
        }

        // actual bonus flow rate is linearly proportional
        // to the total active vote weight / totalSupplyVoteWeight * quorumBps
        uint256 percentageOfQuorum = (totalActiveAllocationWeight * _percentageScale) / votesToReachQuorum;
        if (percentageOfQuorum > _percentageScale) {
            percentageOfQuorum = _percentageScale;
        }

        // actual bonus flow rate is linearly proportional
        // to the total active vote weight / totalSupplyVoteWeight * quorumBps
        int256 computedBonusFlowRate = int256(
            _scaleAmountByPercentage(uint256(uint96(maxBonusFlowRate)), percentageOfQuorum, _percentageScale)
        );

        if (computedBonusFlowRate > type(int96).max) revert IFlow.FLOW_RATE_TOO_HIGH();

        bonusFlowRate = int96(computedBonusFlowRate);

        leftoverFlowRate = maxBonusFlowRate - bonusFlowRate;
    }

    /**
     * @notice Calculates the flow rates for the flow contract
     * @param fs The storage of the Flow contract
     * @param _flowRate The desired flow rate for the flow contract
     * @param _percentageScale The percentage scale
     * @param _totalAllocationWeight The total token supply vote weight
     * @return baselineFlowRate The baseline flow rate
     * @return bonusFlowRate The bonus flow rate
     * @return managerRewardFlowRate The manager reward pool flow rate
     */
    function calculateFlowRates(
        FlowTypes.Storage storage fs,
        int96 _flowRate,
        uint256 _percentageScale,
        uint256 _totalAllocationWeight
    ) external returns (int96 baselineFlowRate, int96 bonusFlowRate, int96 managerRewardFlowRate) {
        int256 managerRewardFlowRatePercent = int256(
            _scaleAmountByPercentage(uint96(_flowRate), fs.managerRewardPoolFlowRatePercent, _percentageScale)
        );

        if (managerRewardFlowRatePercent > type(int96).max) revert IFlow.FLOW_RATE_TOO_HIGH();

        managerRewardFlowRate = int96(managerRewardFlowRatePercent);

        int96 remainingFlowRate = _flowRate - managerRewardFlowRate;

        int256 baselineFlowRate256 = int256(
            _scaleAmountByPercentage(uint96(remainingFlowRate), fs.baselinePoolFlowRatePercent, _percentageScale)
        );

        if (baselineFlowRate256 > type(int96).max) revert IFlow.FLOW_RATE_TOO_HIGH();

        baselineFlowRate = int96(baselineFlowRate256);
        int96 leftoverFlowRate;

        (bonusFlowRate, leftoverFlowRate) = _calculateBonusFlowRate(
            fs,
            _flowRate,
            _percentageScale,
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
    function getActualFlowRate(FlowTypes.Storage storage fs, address flowAddress) external view returns (int96) {
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
     * @notice Multiplies an amount by a scaled percentage
     *  @param amount Amount to get `scaledPercentage` of
     *  @param scaledPercent Percent scaled by PERCENTAGE_SCALE
     *  @return scaledAmount Percent of `amount`.
     */
    function _scaleAmountByPercentage(
        uint256 amount,
        uint256 scaledPercent,
        uint256 percentageScale
    ) public pure returns (uint256 scaledAmount) {
        // use assembly to bypass checking for overflow & division by 0
        // scaledPercent has been validated to be < PERCENTAGE_SCALE)
        // & PERCENTAGE_SCALE will never be 0
        assembly {
            /* eg (100 * 2*1e4) / (1e6) */
            scaledAmount := div(mul(amount, scaledPercent), percentageScale)
        }
    }
}
