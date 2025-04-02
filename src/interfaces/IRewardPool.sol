// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

/**
 * @title IRewardPool
 * @notice Interface for the RewardPool contract
 */
interface IRewardPool {
    /**
     * @notice Initializes the contract and creates a Superfluid pool
     * @param superToken The address of the SuperToken to be used
     * @param manager The address of the manager of the pool
     * @param funder The address of the funder of the pool
     * @param initialOwner The address of the initial owner of the pool
     */
    function initialize(ISuperToken superToken, address manager, address funder, address initialOwner) external;

    /**
     * @notice Allows the admin or owner to update the flow rate of the pool
     * @param flowRate The new flow rate to be set
     */
    function setFlowRate(int96 flowRate) external;

    /**
     * @notice Allows the admin to update member units of pool recipients
     * @param member The address of the pool recipient
     * @param units The new member units to assign to the recipient
     */
    function updateMemberUnits(address member, uint128 units) external;

    /**
     * @notice Retrieves the units for a specific member in the pool
     * @param member The address of the member
     * @return units The units assigned to the member
     */
    function getMemberUnits(address member) external view returns (uint128 units);

    /**
     * @notice Resets the flow rate of the pool to its current total flow rate
     * @dev Only callable by the owner or manager of the reward pool contract
     */
    function resetFlowRate() external;

    /**
     * @notice Retrieves the total flow rate of the pool
     * @return totalFlowRate The total flow rate of the pool
     */
    function getTotalFlowRate() external view returns (int96 totalFlowRate);

    /**
     * @notice Retrieves the actual flow rate of the pool, not the cached value.
     * @return actualFlowRate The actual flow rate of the pool
     */
    function getActualFlowRate() external view returns (int96 actualFlowRate);

    /**
     * @notice Helper function to get the claimable balance for a member at the current time
     * @param member The address of the member
     * @return claimableBalance The claimable balance for the member
     */
    function getClaimableBalanceNow(address member) external view returns (int256 claimableBalance);
}
