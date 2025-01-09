// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { BaseTokenEmitter } from "./BaseTokenEmitter.sol";
import { FlowProtocolRewards } from "../protocol-rewards/abstract/FlowProtocolRewards.sol";

/**
 * @title TokenEmitterETH
 * @dev Child contract for ETH-based token purchasing, extending the abstract BaseTokenEmitter.
 */
contract TokenEmitterETH is BaseTokenEmitter {
    /**
     * @dev This constructor calls the FlowProtocolRewards constructor.
     *      For an upgradable contract, the typical pattern is that this constructor
     *      only runs once at the time the proxy is deployed.
     *      Make sure your proxy deployment is consistent with your environment.
     */
    constructor(
        address _protocolRewards,
        address _protocolFeeRecipient
    )
        payable
        FlowProtocolRewards(_protocolRewards, _protocolFeeRecipient)
        initializer // from OpenZeppelin's Initializable
    {
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
     */
    function checkPayment(uint256 totalPayment) public payable override {
        // Check for underpayment
        if (msg.value < totalPayment) revert INSUFFICIENT_FUNDS();
    }

    /**
     * @notice Handles overpayment
     * @dev If the user sends more ETH than the total payment, the excess is converted to WETH and sent to the user
     */
    function handleOverpayment(uint256 totalPayment) internal override {
        // Handle overpayment
        if (msg.value > totalPayment) {
            _transferPaymentTokenWithFallback(_msgSender(), msg.value - totalPayment);
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
        checkPayment(totalPayment);

        // Handle overpayment
        handleOverpayment(totalPayment);

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
        emit TokensBought(_msgSender(), user, amount, costForTokens, protocolRewardsFee, founderReward);
    }

    /**
     * @notice Transfer ETH/WETH from the contract
     * @dev Attempts to transfer ETH first, falls back to WETH if ETH transfer fails
     * @param _to The recipient address
     * @param _amount The amount transferring
     */
    function _transferPaymentTokenWithFallback(address _to, uint256 _amount) internal override {
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
