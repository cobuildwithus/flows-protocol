// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Interface that combines IVotes and IERC20 for ERC20 tokens with voting capabilities.
 * This interface is used by ERC20Flow to interact with ERC20 voting tokens.
 */
interface IERC20Votes is IVotes, IERC20 {}
