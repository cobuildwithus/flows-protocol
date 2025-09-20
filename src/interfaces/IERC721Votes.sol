// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import { IERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title IERC721Votes
/// @notice A limited version of the ERC721Votes interface from the Nouns DAO on Ethereum mainnet.
interface IERC721Votes is IERC721Enumerable, IVotes {}
