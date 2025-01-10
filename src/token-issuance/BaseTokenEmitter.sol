// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { BondingSCurve } from "../token-issuance/BondingSCurve.sol";
import { VRGDACap } from "../token-issuance/VRGDACap.sol";
import { ERC20VotesMintable } from "../ERC20VotesMintable.sol";
import { ITokenEmitter } from "../interfaces/ITokenEmitter.sol";
import { IWETH } from "../interfaces/IWETH.sol";
import { FlowProtocolRewards } from "../protocol-rewards/abstract/FlowProtocolRewards.sol";
import { toDaysWadUnsafe, wadDiv } from "../libs/SignedWadMath.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title BaseTokenEmitter
 * @dev Abstract contract for emitting tokens using a bonding curve mechanism
 */
abstract contract BaseTokenEmitter is
    ITokenEmitter,
    BondingSCurve,
    VRGDACap,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice The ERC20 token being emitted
    ERC20VotesMintable public erc20;

    /// @notice The WETH token
    IWETH public WETH;

    /// @notice The address for the founder reward
    address public founderRewardAddress;

    /// @notice The timestamp at which the founder reward expires
    uint256 public founderRewardExpiration;

    // The start time of token emission for the VRGDACap
    uint256 public vrgdaCapStartTime;

    // The extra payment received from high VRGDACap prices
    uint256 public vrgdaCapExtraPayment;

    /**
     * @dev Initializes the TokenEmitter contract
     * @param _initialOwner The address of the initial owner of the contract
     * @param _erc20 The address of the ERC20 token to be emitted
     * @param _weth The address of the WETH token
     * @param _founderRewardAddress The address of the founder reward
     * @param _curveSteepness The steepness of the bonding curve
     * @param _basePrice The base price for token emission
     * @param _maxPriceIncrease The maximum price increase for token emission
     * @param _supplyOffset The supply offset for the bonding curve
     * @param _priceDecayPercent The price decay percent for the VRGDACap
     * @param _perTimeUnit The per time unit for the VRGDACap
     * @param _founderRewardDuration The duration of seconds for the founder reward to be active in seconds
     */
    function BaseTokenEmitter__initialize(
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
    ) internal onlyInitializing {
        if (_erc20 == address(0)) revert ADDRESS_ZERO();
        if (_weth == address(0)) revert ADDRESS_ZERO();
        if (_initialOwner == address(0)) revert ADDRESS_ZERO();

        founderRewardAddress = _founderRewardAddress;
        founderRewardExpiration = block.timestamp + _founderRewardDuration;

        erc20 = ERC20VotesMintable(_erc20);
        WETH = IWETH(_weth);

        // If we are upgrading, don't reset the start time
        if (vrgdaCapStartTime == 0) vrgdaCapStartTime = block.timestamp;

        __Ownable_init();

        _transferOwnership(_initialOwner);

        __ReentrancyGuard_init();

        __BondingSCurve_init(_curveSteepness, _basePrice, _maxPriceIncrease, _supplyOffset);
        __VRGDACap_init(_priceDecayPercent, _perTimeUnit);
    }

    /**
     * @notice Calculates the cost to buy a certain amount of tokens
     * @dev Uses the bonding curve to determine the cost
     * @param amount The number of tokens to buy
     * @return totalCost The cost to buy the specified amount of tokens
     * @return addedSurgeCost The extra payment paid by users due to high VRGDACap prices
     * @dev Uses the bonding curve to determine the minimum cost, but if sales are ahead of schedule, the VRGDACap price will be used
     */
    function buyTokenQuote(uint256 amount) public view returns (int256 totalCost, uint256 addedSurgeCost) {
        if (amount == 0) revert INVALID_AMOUNT();

        uint256 founderReward = calculateFounderReward(amount);
        bool founderRewardActive = isFounderRewardActive();

        uint256 totalMintAmount = amount + (founderRewardActive ? founderReward : 0);

        int256 bondingCurveCost = costForToken(int256(erc20.totalSupply()), int256(totalMintAmount));

        int256 avgTargetPrice = wadDiv(bondingCurveCost, int256(totalMintAmount));

        if (avgTargetPrice < 0) {
            avgTargetPrice = 1; // ensure target price is positive
        }

        // not a perfect integration here, but it's more accurate than using basePrice for p_0 in the vrgda
        // shouldn't be issues, but worth triple checking
        int256 vrgdaCapCost = xToY({
            timeSinceStart: toDaysWadUnsafe(block.timestamp - vrgdaCapStartTime),
            sold: int256(erc20.totalSupply()),
            amount: int256(totalMintAmount),
            avgTargetPrice: avgTargetPrice
        });

        if (vrgdaCapCost < 0) revert INVALID_COST();
        if (bondingCurveCost < 0) revert INVALID_COST();

        if (bondingCurveCost >= vrgdaCapCost) {
            totalCost = bondingCurveCost;
            addedSurgeCost = 0;
        } else {
            totalCost = vrgdaCapCost;
            addedSurgeCost = uint256(vrgdaCapCost - bondingCurveCost);
        }
    }

    /**
     * @notice Calculates the payment received when selling a certain amount of tokens
     * @dev Uses the bonding curve to determine the payment
     * @param amount The number of tokens to sell
     * @return payment The payment received for selling the specified amount of tokens
     */
    function sellTokenQuote(uint256 amount) public view returns (int256 payment) {
        return paymentToSell(int256(erc20.totalSupply()), int256(amount));
    }

    /**
     * @notice Collects payment from the user
     * @dev Must be implemented in the child contract
     * @param totalPaymentRequired The total payment amount required
     * @param payment The number of payment tokens the user has sent to pay
     */
    function checkPayment(uint256 totalPaymentRequired, uint256 payment) internal virtual {
        revert NOT_IMPLEMENTED();
    }

    /**
     * @notice Handles overpayment
     * @dev Must be implemented in the child contract
     * @param totalPaymentRequired The total payment amount required
     * @param payment The number of payment tokens the user has sent to pay
     */
    function handleOverpayment(uint256 totalPaymentRequired, uint256 payment) internal virtual {
        revert NOT_IMPLEMENTED();
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
    ) public payable virtual {
        revert NOT_IMPLEMENTED();
    }

    /**
     * @notice Calculates the founder reward for a given amount of tokens
     * @dev 7% of the amount of tokens bought, but at least 1 token (same deal as YCombinator)
     * @param amount The number of tokens to buy
     * @return The amount of founder reward tokens to mint
     */
    function calculateFounderReward(uint256 amount) public view returns (uint256) {
        return amount >= 14 ? (amount * 7) / 100 : 1;
    }

    /**
     * @notice Checks if the founder reward is active
     * @return True if the founder reward is active, false otherwise
     */
    function isFounderRewardActive() public view returns (bool) {
        return founderRewardAddress != address(0) && block.timestamp < founderRewardExpiration;
    }

    /**
     * @notice Allows users to sell tokens and receive a payment token with slippage protection.
     * @dev Only pays back an amount that fits on the bonding curve, does not factor in VRGDACap extra payment.
     * @param amount The number of tokens to sell
     * @param minPayment The minimum acceptable payment in wei
     */
    function sellToken(uint256 amount, uint256 minPayment) public virtual {
        revert NOT_IMPLEMENTED();
    }

    /**
     * @notice Allows the owner to withdraw accumulated VRGDACap payment
     * @dev Plan is to use this to fund a liquidity pool OR fund the Flow grantees for this token
     */
    function withdrawVRGDAPayment() external virtual nonReentrant onlyOwner {
        uint256 amount = vrgdaCapExtraPayment;
        if (amount > 0) {
            vrgdaCapExtraPayment = 0;
            emit VRGDACapPaymentWithdrawn(amount);
            _transferPaymentWithFallback(owner(), amount);
        }
    }

    /**
     * @notice Transfer payment token from the contract
     * @dev Must implement this in the child contract
     * @param _to The recipient address
     * @param _amount The amount transferring
     */
    function _transferPaymentWithFallback(address _to, uint256 _amount) internal virtual {}

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
