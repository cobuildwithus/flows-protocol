// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { BaseTokenEmitter } from "./BaseTokenEmitter.sol";
import { FlowProtocolRewards } from "../protocol-rewards/abstract/FlowProtocolRewards.sol";
import { ITokenEmitterETH } from "../interfaces/ITokenEmitterETH.sol";

/**
 * @title TokenEmitterETH
 * @dev Child contract for ETH-based token purchasing, extending the abstract BaseTokenEmitter.
 */
contract TokenEmitterETH is ITokenEmitterETH, BaseTokenEmitter, FlowProtocolRewards {
    /**
     * @dev This constructor calls the FlowProtocolRewards constructor.
     *      For an upgradable contract, the typical pattern is that this constructor
     *      only runs once at the time the proxy is deployed.
     *      Make sure your proxy deployment is consistent with your environment.
     */
    constructor(
        address _protocolRewards,
        address _protocolFeeRecipient
    ) payable FlowProtocolRewards(_protocolRewards, _protocolFeeRecipient) {
        if (_protocolRewards == address(0)) revert ADDRESS_ZERO();
        if (_protocolFeeRecipient == address(0)) revert ADDRESS_ZERO();
    }

    /**
     * @notice External initializer to set up the contract after deployment (UUPS / Proxy style).
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
        // Call the internal init function on the base
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
     * @notice Collects payment from the user
     * @dev Accepts ETH msg.value
     * @param totalPaymentRequired The total payment amount required
     * @param payment The ETH sent by the user
     */
    function checkPayment(uint256 totalPaymentRequired, uint256 payment) internal override {
        // Check for underpayment
        if (payment < totalPaymentRequired) revert INSUFFICIENT_FUNDS();
    }

    /**
     * @notice Handles overpayment
     * @dev If the user sends more ETH than the total payment, the excess is converted to WETH and sent to the user
     * @param totalPaymentRequired The total payment amount required
     * @param payment The ETH sent by the user
     */
    function handleOverpayment(uint256 totalPaymentRequired, uint256 payment) internal override {
        // Handle overpayment
        if (payment > totalPaymentRequired) {
            _transferPaymentWithFallback(_msgSender(), payment - totalPaymentRequired);
        }
    }

    /**
     * @notice Allows users to buy tokens by sending a payment token with slippage protection
     * @dev Uses nonReentrant modifier to prevent reentrancy attacks
     * @param user The address of the user who received the tokens
     * @param amount The number of tokens to buy
     * @param maxCost The maximum acceptable cost in wei
     */
    function buyToken(
        address user,
        uint256 amount,
        uint256 maxCost,
        ProtocolRewardAddresses calldata protocolRewardsRecipients
    ) public payable virtual override nonReentrant {
        if (user == address(0)) revert ADDRESS_ZERO();
        if (amount == 0) revert INVALID_AMOUNT();

        (int256 costInt, uint256 surgeCost) = buyTokenQuote(amount);
        if (costInt < 0) revert INVALID_COST();
        uint256 costForTokens = uint256(costInt);

        if (costForTokens > maxCost) revert SLIPPAGE_EXCEEDED();

        uint256 protocolRewardsFee = computeTotalReward(costForTokens);
        uint256 totalPayment = costForTokens + protocolRewardsFee;

        // Collect payment
        checkPayment(totalPayment, msg.value);

        // Handle overpayment
        handleOverpayment(totalPayment, msg.value);

        // Share protocol rewards
        _handleRewardsAndGetValueToSend(
            costForTokens, // pass in cost before rewards
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

        //TODO add surgeCost here maybe?
        emit TokensBought(_msgSender(), user, amount, costForTokens, protocolRewardsFee, founderReward, surgeCost);
    }

    /**
     * @notice Allows users to sell tokens and receive a payment token with slippage protection.
     * @dev Only pays back an amount that fits on the bonding curve, does not factor in VRGDACap extra payment.
     * @param amount The number of tokens to sell
     * @param minPayment The minimum acceptable payment in wei
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
     * @notice Calculates the cost to buy a certain amount of tokens including protocol rewards
     * @dev Uses the bonding curve to determine the cost
     * @param amount The number of tokens to buy
     * @return totalCost The cost to buy the specified amount of tokens including protocol rewards
     * @return addedSurgeCost The extra payment paid by users due to high VRGDACap prices
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
     * @notice Transfer ETH/WETH from the contract
     * @dev Attempts to transfer ETH first, falls back to WETH if ETH transfer fails
     * @param _to The recipient address
     * @param _amount The amount transferring
     */
    function _transferPaymentWithFallback(address _to, uint256 _amount) internal override {
        // Ensure the contract has enough ETH to transfer
        if (address(this).balance < _amount) revert("Insufficient balance");

        // Used to store if the transfer succeeded
        bool success;

        assembly {
            // Transfer ETH to the recipient
            // Limit the call to 50,000 gas
            success := call(50000, _to, _amount, 0, 0, 0, 0)
        }

        // If the transfer failed:
        if (!success) {
            // Wrap as WETH
            WETH.deposit{ value: _amount }();

            // Transfer WETH instead
            bool wethSuccess = WETH.transfer(_to, _amount);

            // Ensure successful transfer
            if (!wethSuccess) revert("WETH transfer failed");
        }
    }
}
