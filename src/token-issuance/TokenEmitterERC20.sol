// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { BaseTokenEmitter } from "./BaseTokenEmitter.sol";
import { ITokenEmitterERC20 } from "../interfaces/ITokenEmitterERC20.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TokenEmitterERC20
 * @notice Handles token purchases using ERC20 tokens as payment
 * @dev Extends BaseTokenEmitter to enable ERC20-based token purchases
 *      - Uses founder rewards instead of protocol rewards
 *      - Designed for common use cases where payment is made in ERC20 tokens
 *      - Handles token purchases, sales, and founder reward distribution
 */
contract TokenEmitterERC20 is ITokenEmitterERC20, BaseTokenEmitter {
    using SafeERC20 for IERC20;

    IERC20 public paymentToken;

    /**
     * @dev Empty constructor for proxy deployment pattern
     * @notice Only runs once during proxy deployment - not during upgrades
     */
    constructor() payable {}

    /**
     * @notice Initializes contract state after proxy deployment
     * @dev Uses UUPS proxy pattern - called only once after deployment
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
        address _paymentToken
    ) public initializer {
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
    }

    /**
     * @notice Internal initialization logic to set up contract state
     * @dev Validates payment token and initializes base contract parameters
     */
    function _handleInitialization(
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
        address _paymentToken
    ) internal {
        if (_paymentToken == address(0)) revert ADDRESS_ZERO();

        paymentToken = IERC20(_paymentToken);

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
     * @notice Validates user has sufficient balance and allowance for payment
     * @dev Non-payable since payment is in ERC20 tokens
     * @param totalPayment Required payment amount in payment tokens
     * @param payer Address that will pay for the purchase
     */
    function checkPayment(uint256 totalPayment, address payer) internal {
        uint256 allowance = paymentToken.allowance(payer, address(this));
        uint256 balance = paymentToken.balanceOf(payer);

        if (balance < totalPayment) {
            revert INSUFFICIENT_FUNDS();
        }

        if (paymentToken.allowance(payer, address(this)) < totalPayment) {
            revert INSUFFICIENT_FUNDS();
        }
    }

    /**
     * @notice Purchases tokens using ERC20 payment with slippage protection
     * @dev Handles token minting, founder rewards, and surge pricing
     * @param user Address to receive the purchased tokens
     * @param amount Number of tokens to purchase
     * @param maxCost Maximum acceptable cost in payment tokens
     */
    function buyToken(
        address user,
        uint256 amount,
        uint256 maxCost,
        ProtocolRewardAddresses calldata protocolRewardsRecipients
    ) public payable virtual override nonReentrant {
        _buyToken(_msgSender(), user, amount, maxCost, protocolRewardsRecipients);
    }

    /**
     * @notice Internal function to handle token purchase with ERC20 payment
     * @dev Validates inputs and handles token minting. Called by public buyToken()
     *      and FlowTokenEmitter's buyWithETH(). When called by FlowTokenEmitter,
     *      payment tokens are pre-purchased and transferred.
     * @param payer Address that will pay for the purchase
     * @param user Address that will receive the purchased tokens
     * @param amount Number of tokens to purchase
     * @param maxCost Maximum payment token cost user is willing to pay (slippage protection)
     * @param protocolRewardsRecipients Struct containing builder and referral addresses for rewards
     */
    function _buyToken(
        address payer,
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

        if (costForTokens > maxCost) revert SLIPPAGE_EXCEEDED();

        uint256 totalPayment = costForTokens;

        checkPayment(totalPayment, payer);

        // Handle payment transfer - skips if called by FlowTokenEmitter which pre-purchases tokens
        if (payer != address(this)) {
            paymentToken.safeTransferFrom(payer, address(this), totalPayment);
        }

        if (surgeCost > 0) {
            vrgdaCapExtraPayment += surgeCost;
        }

        erc20.mint(user, amount);

        uint256 founderReward = calculateFounderReward(amount);
        if (isFounderRewardActive()) {
            erc20.mint(founderRewardAddress, founderReward);
        }

        emit TokensBought(payer, user, amount, costForTokens, 0, founderReward, surgeCost);
    }

    /**
     * @notice Transfers ERC20 payment tokens from contract to recipient
     * @param _to Recipient address
     * @param _amount Amount of tokens to transfer
     */
    function _transferPaymentWithFallback(address _to, uint256 _amount) internal override {
        paymentToken.safeTransfer(_to, _amount);
    }

    /**
     * @notice Sells tokens back to the contract for payment tokens
     * @dev Validates balances and handles token burning and payment
     * @param amount Amount of tokens to sell
     * @param minPayment Minimum acceptable payment to receive
     */
    function sellToken(uint256 amount, uint256 minPayment) public virtual override nonReentrant {
        int256 paymentInt = sellTokenQuote(amount);
        if (paymentInt < 0) revert INVALID_PAYMENT();
        if (amount == 0) revert INVALID_AMOUNT();
        uint256 payment = uint256(paymentInt);

        if (payment < minPayment) revert SLIPPAGE_EXCEEDED();
        if (payment > paymentToken.balanceOf(address(this))) revert INSUFFICIENT_CONTRACT_BALANCE();
        if (erc20.balanceOf(_msgSender()) < amount) revert INSUFFICIENT_TOKEN_BALANCE();

        erc20.burn(_msgSender(), amount);

        _transferPaymentWithFallback(_msgSender(), payment);

        emit TokensSold(_msgSender(), amount, payment);
    }

    /**
     * @notice Transfers ETH with WETH fallback if direct transfer fails
     * @dev Attempts ETH transfer first, wraps to WETH if needed
     * @param _to Recipient address
     * @param _amount Amount of ETH/WETH to transfer
     */
    function _transferETHWithFallback(address _to, uint256 _amount) internal {
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
