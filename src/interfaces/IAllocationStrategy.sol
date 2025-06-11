// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/// @notice Externalized source of allocation keys & weight.
interface IAllocationStrategy {
    /// unique key used to index this allocation inside Flow.storage
    /// this will be overwritten when a new vote is cast
    /// so for example we want to make sure this is the tokenId of the token that is being voted with
    function allocationKey(address caller, bytes calldata aux) external view returns (uint256);

    /// live voting power for that key
    function currentWeight(uint256 key) external view returns (uint256);

    /// optional safety hook – Flow may revert if false
    function canAllocate(uint256 key, address caller) external view returns (bool);

    /// optional function that helps calculate quorum
    function totalAllocationWeight() external view returns (uint256);

    /// @notice Returns the expected top-level JSON field name for this strategy.
    ///         Frontends can read this to construct the JSON payload for `buildAllocationData`.
    function jsonKey() external pure returns (string memory);

    /**
     * @notice Pure helper that turns arbitrary JSON into the
     *         bytes expected by Flow.allocate().
     * @dev Useful for frontend to build the allocation data.
     *      MUST be pure or view so dApps can call it off-chain.
     *
     * Example JSON for an ERC-721 voting strategy:
     *   { "tokenId": "42" }
     */
    function buildAllocationData(address caller, string memory json) external pure returns (bytes[] memory aux);

    /// Errors
    error ADDRESS_ZERO();
}
