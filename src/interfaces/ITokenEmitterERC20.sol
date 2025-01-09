// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { IERC20VotesMintable } from "./IERC20VotesMintable.sol";

/**
 * @title ITokenEmitterERC20
 * @dev Interface for the TokenEmitterERC20 contract
 */
interface ITokenEmitterERC20 {
    /**
     * @dev Initializes the TokenEmitterERC20 contract
     * @param initialOwner The address of the initial owner of the contract
     * @param erc20 The address of the ERC20 token to be emitted
     * @param weth The address of the WETH token
     * @param founderRewardAddress The address of the founder reward
     * @param curveSteepness The steepness of the bonding curve
     * @param basePrice The base price for token emission
     * @param maxPriceIncrease The maximum price increase for token emission
     * @param supplyOffset The supply offset for the bonding curve
     * @param priceDecayPercent The price decay percent for the VRGDACap
     * @param perTimeUnit The per time unit for the VRGDACap
     * @param founderRewardDuration The duration for the founder reward in seconds from the deployed timestamp
     * @param paymentToken The address of the payment token
     */
    function initialize(
        address initialOwner,
        address erc20,
        address weth,
        address founderRewardAddress,
        int256 curveSteepness,
        int256 basePrice,
        int256 maxPriceIncrease,
        int256 supplyOffset,
        int256 priceDecayPercent,
        int256 perTimeUnit,
        uint256 founderRewardDuration,
        address paymentToken
    ) external;
}
