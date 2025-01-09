// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { BaseTokenEmitter } from "./BaseTokenEmitter.sol";
import { FlowProtocolRewards } from "../protocol-rewards/abstract/FlowProtocolRewards.sol";
import { ITokenEmitterERC20 } from "../interfaces/ITokenEmitterERC20.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TokenEmitterERC20
 * @dev Child contract for ERC20-based token purchasing, extending the abstract BaseTokenEmitter.
 */
contract TokenEmitterERC20 is ITokenEmitterERC20, BaseTokenEmitter {
    using SafeERC20 for IERC20;

    IERC20 public paymentToken;

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
        uint256 _founderRewardDuration,
        address _paymentToken
    ) external initializer {
        if (_paymentToken == address(0)) revert ADDRESS_ZERO();

        paymentToken = IERC20(_paymentToken);

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
     * @notice Collects payment from the user (ERC20 style).
     * @dev We remove `payable` since we are not using `msg.value` or ETH here.
     * @param totalPayment The total number of payment tokens required
     * @param balance The number of payment tokens the user has on balance
     */
    function checkPayment(uint256 totalPayment, uint256 balance) internal override {
        // 1. Ensure user has enough balance to pay
        if (balance < totalPayment) {
            revert INSUFFICIENT_FUNDS(); // or a more appropriate error like "Insufficient allowance"
        }

        // 2. Ensure user has approved this contract to spend at least `totalPayment`.
        if (paymentToken.allowance(_msgSender(), address(this)) < totalPayment) {
            revert INSUFFICIENT_FUNDS();
        }

        // 3. Transfer exactly `totalPayment` from the user to this contract.
        paymentToken.safeTransferFrom(_msgSender(), address(this), totalPayment);
    }

    /**
     * @notice Handles overpayment (ERC20 typically doesn't do "overpayment" flow).
     * @dev In many ERC20 flows, we just do an exact `transferFrom`. This can be a no-op.
     */
    function handleOverpayment(uint256 /* totalPayment */, uint256 /* amount */) internal override {
        // For ERC20, if the user calls `transferFrom` for exactly totalPayment, there's no overpayment.
        // We can simply do nothing or revert if called unexpectedly.
    }

    /**
     * @notice Allows users to buy tokens with an ERC20 token with slippage protection.
     * @dev This is roughly analogous to the ETH-based buy but we do not rely on `msg.value`.
     * @param user The address that will receive the minted tokens
     * @param amount The number of tokens to buy
     * @param maxCost The maximum acceptable cost in "paymentToken" units
     * @param protocolRewardsRecipients Splits for protocol-level affiliate or builder rewards
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

        // Calculate protocol fee
        uint256 protocolRewardsFee = computeTotalReward(costForTokens);
        uint256 totalPayment = costForTokens + protocolRewardsFee;

        // 1. Transfer exactly `totalPayment` from user => contract
        checkPayment(totalPayment, paymentToken.balanceOf(_msgSender()));

        // 2. Overpayment is not applicable in ERC20 flow

        // 3. If there's a surge cost, track it
        if (surgeCost > 0) {
            vrgdaCapExtraPayment += surgeCost;
        }

        // 4. Mint the purchased tokens
        erc20.mint(user, amount);

        // 5. Possibly mint founder reward
        uint256 founderReward = calculateFounderReward(amount);
        if (isFounderRewardActive()) {
            erc20.mint(founderRewardAddress, founderReward);
        }

        emit TokensBought(_msgSender(), user, amount, costForTokens, protocolRewardsFee, founderReward, surgeCost);
    }

    /**
     * @notice Transfer ERC20 tokens from the contract
     * @param _to The recipient address
     * @param _amount The amount transferring
     */
    function _transferPaymentWithFallback(address _to, uint256 _amount) internal override {
        paymentToken.safeTransfer(_to, _amount);
    }

    /**
     * @notice Override sellToken to check ERC20 balance instead of ETH balance
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
     * @notice Transfer ETH/WETH from the contract
     * @dev Attempts to transfer ETH first, falls back to WETH if ETH transfer fails
     * @param _to The recipient address
     * @param _amount The amount transferring
     */
    function _transferETHWithFallback(address _to, uint256 _amount) internal {
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
