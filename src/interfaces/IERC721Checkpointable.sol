// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

/// @title IERC721Checkpointable
/// @notice A limited version of the ERC721Checkpointable interface from the nouns-monorepo
/// @dev This interface is specifically designed for the NounsToken used by the Nouns DAO on Ethereum mainnet.
interface IERC721Checkpointable is IERC721Enumerable {
    /// @notice Get the current number of votes for an account
    /// @param account The address of the account to check
    /// @return The number of votes as a uint96
    function getCurrentVotes(address account) external view returns (uint96);

    /// @notice Get the number of votes for an account at a specific block number
    /// @param account The address of the account to check
    /// @param blockNumber The block number to get the vote count at
    /// @return The number of votes as a uint96
    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint96);

    /// @notice Get the delegate address for a given delegator
    /// @dev This function overrides the standard `Comp.sol` delegates mapping to return
    ///      the delegator's own address if they haven't delegated. This avoids having to delegate to oneself.
    /// @param delegator The address of the delegator
    /// @return The address of the delegate
    function delegates(address delegator) external view returns (address);
}
