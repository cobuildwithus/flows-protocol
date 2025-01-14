// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { TokenEmitterERC20 } from "./TokenEmitterERC20.sol";
import { TokenEmitterETH } from "./TokenEmitterETH.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ITokenEmitter } from "../interfaces/ITokenEmitter.sol";
import { IFlowTokenEmitter } from "../interfaces/IFlowTokenEmitter.sol";

/**
 * @title FlowTokenEmitter
 * @notice Extends TokenEmitterERC20 to enable ETH purchases of Flow tokens through a two-step process:
 * 1. ETH is used to acquire payment tokens from a TokenEmitterETH contract
 * 2. Payment tokens are then used to purchase Flow tokens
 */
contract FlowTokenEmitter is IFlowTokenEmitter, TokenEmitterERC20 {
    using SafeERC20 for IERC20;

    /// @notice Reference to the TokenEmitterETH contract that mints/sells the payment token
    TokenEmitterETH public ethEmitter;

    constructor() TokenEmitterERC20() {}

    /**
     * @notice Initializes the contract with configuration parameters
     * @param _initialOwner Address of the contract owner
     * @param _erc20 Address of the Flow token contract
     * @param _weth Address of the WETH contract
     * @param _founderRewardAddress Address to receive founder rewards
     * @param _curveSteepness Bonding curve steepness parameter
     * @param _basePrice Base price for token purchases
     * @param _maxPriceIncrease Maximum allowed price increase
     * @param _supplyOffset Initial supply offset
     * @param _priceDecayPercent Price decay percentage
     * @param _perTimeUnit Tokens per time unit
     * @param _founderRewardDuration Duration of founder reward distribution
     * @param _paymentToken Address of the payment token
     * @param _ethEmitter Address of the TokenEmitterETH contract
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
        uint256 _founderRewardDuration,
        address _paymentToken,
        address _ethEmitter
    ) external initializer {
        _handleInitialization(
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
            _founderRewardDuration,
            _paymentToken
        );

        if (_ethEmitter == address(0)) revert("Invalid ETH emitter");
        ethEmitter = TokenEmitterETH(_ethEmitter);
    }

    /**
     * @notice Calculates the total ETH cost for purchasing a given amount of Flow tokens
     * @param tokenAmount The amount of Flow tokens to purchase
     * @return totalCostInETH The total ETH cost including surge pricing
     * @return addedSurgeCostInETH The additional surge cost component
     */
    function buyTokenQuoteETH(
        uint256 tokenAmount
    ) external view returns (int256 totalCostInETH, uint256 addedSurgeCostInETH) {
        (int256 costInPaymentTokensInt, ) = buyTokenQuote(tokenAmount);
        if (costInPaymentTokensInt < 0) revert INVALID_COST();
        uint256 costInPaymentTokens = uint256(costInPaymentTokensInt);

        (int256 costInETHInt, uint256 surgeCostInETH) = ethEmitter.buyTokenQuoteWithRewards(costInPaymentTokens);
        if (costInETHInt < 0) revert INVALID_COST();

        totalCostInETH = costInETHInt;
        addedSurgeCostInETH = surgeCostInETH;
    }

    /**
     * @notice Purchases Flow tokens using ETH through a two-step process
     * @dev First acquires payment tokens from ethEmitter, then uses those to buy Flow tokens
     * @param user Address to receive the Flow tokens
     * @param tokenAmount Amount of Flow tokens to purchase
     * @param maxCost Maximum ETH cost allowed for the purchase
     * @param protocolRewardsRecipients Addresses for protocol reward distribution
     */
    function buyWithETH(
        address user,
        uint256 tokenAmount,
        uint256 maxCost,
        ITokenEmitter.ProtocolRewardAddresses calldata protocolRewardsRecipients
    ) external payable nonReentrant {
        _buyWithETH(user, tokenAmount, maxCost, protocolRewardsRecipients);
    }

    /**
     * @notice Internal function to handle ETH-to-Flow token purchase flow
     * @dev Two step process:
     *      1. Uses ETH to purchase payment tokens from ethEmitter
     *      2. Uses acquired payment tokens to purchase Flow tokens
     *      Handles slippage protection and protocol rewards
     * @param user Address that will receive the Flow tokens
     * @param tokenAmount Amount of Flow tokens to mint to the user
     * @param maxCost Maximum ETH cost user is willing to pay (slippage protection)
     * @param protocolRewardsRecipients Struct containing builder and referral addresses for reward distribution
     */
    function _buyWithETH(
        address user,
        uint256 tokenAmount,
        uint256 maxCost,
        ITokenEmitter.ProtocolRewardAddresses calldata protocolRewardsRecipients
    ) internal {
        if (user == address(0)) revert ADDRESS_ZERO();
        if (tokenAmount == 0) revert INVALID_AMOUNT();
        if (msg.value == 0) revert INVALID_PAYMENT();

        // Calculate payment token cost
        (int256 costInt, ) = buyTokenQuote(tokenAmount);
        if (costInt < 0) revert INVALID_COST();
        uint256 costInPaymentTokens = uint256(costInt);

        // Calculate ETH cost for payment tokens
        (int256 costInETHInt, ) = ethEmitter.buyTokenQuoteWithRewards(costInPaymentTokens);
        if (costInETHInt < 0) revert INVALID_COST();
        uint256 costInETH = uint256(costInETHInt);
        if (costInETH > maxCost) revert SLIPPAGE_EXCEEDED();
        if (costInETH > msg.value) revert INSUFFICIENT_FUNDS();

        // Track payment token balance changes
        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(address(this));

        // Purchase payment tokens with ETH
        ethEmitter.buyToken{ value: costInETH }(address(this), costInPaymentTokens, maxCost, protocolRewardsRecipients);

        uint256 paymentTokenAcquired = paymentToken.balanceOf(address(this)) - paymentTokenBalanceBefore;
        if (paymentTokenAcquired < costInPaymentTokens) revert INSUFFICIENT_PAYMENT_TOKENS();

        // Use payment tokens to purchase Flow tokens
        paymentToken.safeIncreaseAllowance(address(this), paymentTokenAcquired);
        _buyToken(address(this), user, tokenAmount, paymentTokenAcquired, protocolRewardsRecipients);

        // Handle excess ETH payment
        handleETHOverpayment(costInETH, msg.value);
    }

    /**
     * @notice Handles excess ETH sent by returning it to the sender
     * @param totalPaymentRequired The required ETH payment amount
     * @param payment The actual ETH amount sent
     */
    function handleETHOverpayment(uint256 totalPaymentRequired, uint256 payment) internal {
        if (payment > totalPaymentRequired) {
            address _to = _msgSender();
            uint256 overpaid = payment - totalPaymentRequired;
            if (address(this).balance < overpaid) revert("Insufficient balance");

            (bool success, ) = _to.call{ value: overpaid, gas: 50000 }("");

            if (!success) {
                WETH.deposit{ value: overpaid }();
                bool wethSuccess = WETH.transfer(_to, overpaid);
                if (!wethSuccess) revert("WETH transfer failed");
            }
        }
    }
}
