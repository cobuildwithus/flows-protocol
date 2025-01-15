// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { IERC20VotesMintable } from "./IERC20VotesMintable.sol";

/**
 * @title ITokenEmitter
 * @dev Interface for the TokenEmitter contract
 */
interface ITokenEmitter {
    /**
     * @dev Struct for the protocol reward addresses
     * @param builder The address of the builder
     * @param purchaseReferral The address of the purchase referral
     */
    struct ProtocolRewardAddresses {
        address builder;
        address purchaseReferral;
    }

    /**
     * @dev Error thrown when the slippage exceeds user's specified limits
     */
    error SLIPPAGE_EXCEEDED();

    /**
     * @dev Error thrown when the address is zero
     */
    error ADDRESS_ZERO();

    /**
     * @dev Error thrown when the user does not have enough funds to buy tokens
     */
    error INSUFFICIENT_FUNDS();

    /**
     * @dev Error thrown when the user does not have enough balance to sell tokens
     */
    error INSUFFICIENT_TOKEN_BALANCE();

    /**
     * @dev Error thrown when the contract does not have enough funds to buy back tokens
     */
    error INSUFFICIENT_CONTRACT_BALANCE();

    /**
     * @dev Error thrown when the cost is invalid
     */
    error INVALID_COST();

    /**
     * @dev Error thrown when the payment is invalid
     */
    error INVALID_PAYMENT();

    /**
     * @dev Event emitted when tokens are bought
     * @param buyer The address of the token buyer
     * @param user The address of the user who received the tokens
     * @param amount The amount of tokens bought
     * @param cost The cost paid for the tokens
     * @param protocolRewards The amount of protocol rewards paid
     * @param founderRewards The amount of founder rewards paid in the token
     */
    event TokensBought(
        address indexed buyer,
        address indexed user,
        uint256 amount,
        uint256 cost,
        uint256 protocolRewards,
        uint256 founderRewards
    );

    /**
     * @dev Event emitted when tokens are sold
     * @param seller The address of the token seller
     * @param amount The amount of tokens sold
     * @param payment The payment received for the tokens
     */
    event TokensSold(address indexed seller, uint256 amount, uint256 payment);

    /**
     * @dev Event emitted when ETH is withdrawn from the VRGDACap
     * @param amount The amount of ETH withdrawn
     */
    event VRGDACapETHWithdrawn(uint256 amount);

    /**
     * @dev Initializes the TokenEmitter contract
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
        uint256 founderRewardDuration
    ) external;

    /**
     * @dev Calculates the cost to buy a certain amount of tokens
     * @param amount The number of tokens to buy
     * @return totalCost The cost to buy the specified amount of tokens
     * @return surgeCost The cost to buy the specified amount of tokens
     */
    function buyTokenQuote(uint256 amount) external view returns (int256 totalCost, uint256 surgeCost);

    /**
     * @dev Calculates the payment received when selling a certain amount of tokens
     * @param amount The number of tokens to sell
     * @return The payment received for selling the specified amount of tokens
     */
    function sellTokenQuote(uint256 amount) external view returns (int256);
}
