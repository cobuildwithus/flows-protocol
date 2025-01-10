// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { BaseTokenEmitter } from "./BaseTokenEmitter.sol";
import { FlowProtocolRewards } from "../protocol-rewards/abstract/FlowProtocolRewards.sol";
import { ITokenEmitterETH } from "../interfaces/ITokenEmitterETH.sol";

/**
 * @title TokenEmitterETH
 * @notice Handles ETH-based token purchases and sales using a bonding curve and VRGDA pricing
 * @dev Extends BaseTokenEmitter to enable native ETH payments with WETH fallback
 *      - Includes protocol reward distribution
 *      - Uses founder rewards instead of protocol rewards for token purchases
 *      - Handles token purchases, sales, and founder reward distribution
 */
contract TokenEmitterETH is ITokenEmitterETH, BaseTokenEmitter, FlowProtocolRewards {
    /**
     * @notice Initializes protocol reward parameters
     * @dev Only runs once during proxy deployment, not during upgrades
     * @param _protocolRewards Address of protocol rewards contract
     * @param _protocolFeeRecipient Address receiving protocol fees
     */
    constructor(
        address _protocolRewards,
        address _protocolFeeRecipient
    ) payable FlowProtocolRewards(_protocolRewards, _protocolFeeRecipient) {
        if (_protocolRewards == address(0)) revert ADDRESS_ZERO();
        if (_protocolFeeRecipient == address(0)) revert ADDRESS_ZERO();
    }

    /**
     * @notice Initializes contract state after proxy deployment
     * @dev Uses UUPS proxy pattern - called only once after deployment
     * @param _initialOwner Address of initial contract owner
     * @param _erc20 Address of token being distributed
     * @param _weth Address of WETH contract for ETH wrapping
     * @param _founderRewardAddress Address receiving founder rewards
     * @param _curveSteepness Steepness parameter for bonding curve
     * @param _basePrice Base price for token distribution
     * @param _maxPriceIncrease Maximum price increase allowed
     * @param _supplyOffset Initial supply offset for curve
     * @param _priceDecayPercent Decay rate for VRGDA pricing
     * @param _perTimeUnit Time unit for VRGDA calculations
     * @param _founderRewardDuration Duration founder rewards remain active
     */
    function initialize(
        address _initialOwner,
        address _erc20,
        address _weth,
        address _founderRewardAddress,
        int256 _curveSteepness,
        int256 _basePrice,
        int256 _maxPriceIncrease,
        int256 _supplyOffset,
        int256 _priceDecayPercent,
        int256 _perTimeUnit,
        uint256 _founderRewardDuration
    ) external initializer {
        BaseTokenEmitter__initialize(
            _initialOwner,
            _erc20,
            _weth,
            _founderRewardAddress,
            _curveSteepness,
            _basePrice,
            _maxPriceIncrease,
            _supplyOffset,
            _priceDecayPercent,
            _perTimeUnit,
            _founderRewardDuration
        );
    }

    /**
     * @notice Validates that sufficient ETH payment was provided
     * @dev Reverts if payment amount is insufficient
     * @param totalPaymentRequired Required payment amount in wei
     * @param payment Actual ETH payment received
     */
    function checkPayment(uint256 totalPaymentRequired, uint256 payment) internal {
        if (payment < totalPaymentRequired) revert INSUFFICIENT_FUNDS();
    }

    /**
     * @notice Returns excess ETH payment to sender
     * @dev Converts to WETH if direct ETH transfer fails
     * @param totalPaymentRequired Required payment amount in wei
     * @param payment Actual ETH payment received
     */
    function handleOverpayment(uint256 totalPaymentRequired, uint256 payment) internal {
        if (payment > totalPaymentRequired) {
            _transferPaymentWithFallback(_msgSender(), payment - totalPaymentRequired);
        }
    }

    /**
     * @notice Purchases tokens with ETH payment
     * @dev Includes slippage protection and protocol rewards
     * @param user Address receiving purchased tokens
     * @param amount Number of tokens to purchase
     * @param maxCost Maximum acceptable cost in wei
     * @param protocolRewardsRecipients Addresses receiving protocol rewards
     */
    function buyToken(
        address user,
        uint256 amount,
        uint256 maxCost,
        ProtocolRewardAddresses calldata protocolRewardsRecipients
    ) public payable virtual override nonReentrant {
        _buyToken(user, amount, maxCost, protocolRewardsRecipients);
    }

    /**
     * @notice Internal function to handle token purchase logic with ETH payment
     * @dev Validates inputs, calculates costs, handles payments and minting
     * @param user Address receiving purchased tokens
     * @param amount Number of tokens to purchase
     * @param maxCost Maximum acceptable cost in wei to prevent slippage
     * @param protocolRewardsRecipients Addresses receiving protocol reward fees
     */
    function _buyToken(
        address user,
        uint256 amount,
        uint256 maxCost,
        ProtocolRewardAddresses calldata protocolRewardsRecipients
    ) internal {
        if (user == address(0)) revert ADDRESS_ZERO();
        if (amount == 0) revert INVALID_AMOUNT();

        (int256 costInt, uint256 surgeCost) = buyTokenQuote(amount);
        if (costInt < 0) revert INVALID_COST();
        uint256 costForTokens = uint256(costInt);

        uint256 protocolRewardsFee = computeTotalReward(costForTokens);
        uint256 totalPayment = costForTokens + protocolRewardsFee;

        if (totalPayment > maxCost) revert SLIPPAGE_EXCEEDED();

        checkPayment(totalPayment, msg.value);

        _handleRewardsAndGetValueToSend(
            costForTokens,
            protocolRewardsRecipients.builder,
            protocolRewardsRecipients.purchaseReferral
        );

        if (surgeCost > 0) {
            vrgdaCapExtraPayment += surgeCost;
        }

        erc20.mint(user, amount);

        uint256 founderReward = calculateFounderReward(amount);
        if (isFounderRewardActive()) {
            erc20.mint(founderRewardAddress, founderReward);
        }

        handleOverpayment(totalPayment, msg.value);

        emit TokensBought(_msgSender(), user, amount, costForTokens, protocolRewardsFee, founderReward, surgeCost);
    }

    /**
     * @notice Sells tokens back to the contract
     * @dev Returns ETH based on bonding curve price, includes slippage protection
     * @param amount Number of tokens to sell
     * @param minPayment Minimum acceptable payment in wei
     */
    function sellToken(uint256 amount, uint256 minPayment) public virtual override nonReentrant {
        int256 paymentInt = sellTokenQuote(amount);
        if (paymentInt < 0) revert INVALID_PAYMENT();
        if (amount == 0) revert INVALID_AMOUNT();
        uint256 payment = uint256(paymentInt);

        if (payment < minPayment) revert SLIPPAGE_EXCEEDED();
        if (payment > address(this).balance) revert INSUFFICIENT_CONTRACT_BALANCE();
        if (erc20.balanceOf(_msgSender()) < amount) revert INSUFFICIENT_TOKEN_BALANCE();

        erc20.burn(_msgSender(), amount);
        _transferPaymentWithFallback(_msgSender(), payment);

        emit TokensSold(_msgSender(), amount, payment);
    }

    /**
     * @notice Calculates total cost including protocol rewards
     * @dev Combines bonding curve price with protocol reward fees
     * @param amount Number of tokens to quote
     * @return totalCost Total cost in wei including protocol rewards
     * @return addedSurgeCost Additional cost from VRGDA surge pricing
     */
    function buyTokenQuoteWithRewards(
        uint256 amount
    ) public view virtual returns (int256 totalCost, uint256 addedSurgeCost) {
        (int256 costInt, uint256 surgeCost) = buyTokenQuote(amount);
        if (costInt < 0) revert INVALID_COST();

        totalCost = costInt + int256(computeTotalReward(uint256(costInt)));
        addedSurgeCost = surgeCost;
    }

    /**
     * @notice Transfers ETH or WETH to recipient
     * @dev Attempts ETH transfer first, falls back to WETH if ETH transfer fails
     * @param _to Recipient address
     * @param _amount Amount to transfer in wei
     */
    function _transferPaymentWithFallback(address _to, uint256 _amount) internal override {
        if (address(this).balance < _amount) revert("Insufficient balance");

        bool success;
        assembly {
            success := call(50000, _to, _amount, 0, 0, 0, 0)
        }

        if (!success) {
            WETH.deposit{ value: _amount }();
            bool wethSuccess = WETH.transfer(_to, _amount);
            if (!wethSuccess) revert("WETH transfer failed");
        }
    }
}
