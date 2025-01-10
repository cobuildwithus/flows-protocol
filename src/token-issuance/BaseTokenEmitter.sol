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
 * @notice Abstract base contract implementing core token emission functionality using a bonding curve
 * and Variable Rate Gradual Dutch Auction (VRGDA) pricing mechanism.
 * @dev Combines bonding curve pricing with VRGDA caps to manage token distribution and price discovery.
 * Inherits from multiple OpenZeppelin security and upgrade patterns.
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

    /// @notice The primary token being distributed through this emitter
    ERC20VotesMintable public erc20;

    /// @notice WETH contract for handling ETH-based operations
    IWETH public WETH;

    /// @notice Recipient address for founder reward distributions
    address public founderRewardAddress;

    /// @notice Unix timestamp after which founder rewards cease
    uint256 public founderRewardExpiration;

    /// @notice Unix timestamp marking the start of VRGDA price calculations
    uint256 public vrgdaCapStartTime;

    /// @notice Accumulated surplus payments from VRGDA price premiums
    uint256 public vrgdaCapExtraPayment;

    /**
     * @notice Initializes the token emitter with core configuration parameters
     * @dev Should only be called once during contract deployment or upgrade
     * @param _initialOwner Address receiving contract ownership and admin rights
     * @param _erc20 Token contract address being distributed
     * @param _weth WETH contract address for ETH operations
     * @param _founderRewardAddress Recipient of founder reward tokens
     * @param _curveSteepness Controls price sensitivity to supply changes
     * @param _basePrice Starting price point for the bonding curve
     * @param _maxPriceIncrease Maximum allowed price growth from base
     * @param _supplyOffset Initial supply adjustment for price calculations
     * @param _priceDecayPercent Rate of VRGDA price decay
     * @param _perTimeUnit Target emission rate per time unit
     * @param _founderRewardDuration Duration in seconds founder rewards remain active
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

        // Preserve existing start time during upgrades
        if (vrgdaCapStartTime == 0) vrgdaCapStartTime = block.timestamp;

        __Ownable_init();
        _transferOwnership(_initialOwner);
        __ReentrancyGuard_init();
        __BondingSCurve_init(_curveSteepness, _basePrice, _maxPriceIncrease, _supplyOffset);
        __VRGDACap_init(_priceDecayPercent, _perTimeUnit);
    }

    /**
     * @notice Calculates total cost and surge pricing for purchasing tokens
     * @dev Combines bonding curve base price with VRGDA price caps
     * @param amount Number of tokens to purchase
     * @return totalCost Final cost including any surge pricing
     * @return addedSurgeCost Premium above base bonding curve price
     */
    function buyTokenQuote(uint256 amount) public view returns (int256 totalCost, uint256 addedSurgeCost) {
        if (amount == 0) revert INVALID_AMOUNT();

        uint256 founderReward = calculateFounderReward(amount);
        bool founderRewardActive = isFounderRewardActive();

        uint256 totalMintAmount = amount + (founderRewardActive ? founderReward : 0);

        int256 bondingCurveCost = costForToken(int256(erc20.totalSupply()), int256(totalMintAmount));
        int256 avgTargetPrice = wadDiv(bondingCurveCost, int256(totalMintAmount));

        // Ensure positive target price for VRGDA calculations
        if (avgTargetPrice < 0) {
            avgTargetPrice = 1;
        }

        int256 vrgdaCapCost = xToY({
            timeSinceStart: toDaysWadUnsafe(block.timestamp - vrgdaCapStartTime),
            sold: int256(erc20.totalSupply()),
            amount: int256(totalMintAmount),
            avgTargetPrice: avgTargetPrice
        });

        if (vrgdaCapCost < 0) revert INVALID_COST();
        if (bondingCurveCost < 0) revert INVALID_COST();

        // Use higher of bonding curve or VRGDA price
        if (bondingCurveCost >= vrgdaCapCost) {
            totalCost = bondingCurveCost;
            addedSurgeCost = 0;
        } else {
            totalCost = vrgdaCapCost;
            addedSurgeCost = uint256(vrgdaCapCost - bondingCurveCost);
        }
    }

    /**
     * @notice Calculates payment for selling tokens back to the contract
     * @dev Uses pure bonding curve pricing without VRGDA adjustments
     * @param amount Number of tokens to sell
     * @return payment Amount of payment tokens to receive
     */
    function sellTokenQuote(uint256 amount) public view returns (int256 payment) {
        return paymentToSell(int256(erc20.totalSupply()), int256(amount));
    }

    /**
     * @notice Template for token purchase implementation
     * @dev Must be implemented by child contracts with reentrancy protection
     * @param user Recipient of purchased tokens
     * @param amount Number of tokens to purchase
     * @param maxCost Maximum acceptable cost
     * @param protocolRewardsRecipients Addresses for protocol reward distribution
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
     * @notice Calculates founder reward allocation
     * @dev Returns 7% of purchase amount (min 1 token) following Y Combinator model
     * @param amount Base token purchase amount
     * @return Founder reward token amount
     */
    function calculateFounderReward(uint256 amount) public view returns (uint256) {
        return amount >= 15 ? (amount * 7) / 100 : 1;
    }

    /**
     * @notice Checks if founder rewards are currently active
     * @return bool True if founder address is set and time period hasn't expired
     */
    function isFounderRewardActive() public view returns (bool) {
        return founderRewardAddress != address(0) && block.timestamp < founderRewardExpiration;
    }

    /**
     * @notice Template for token sell implementation
     * @dev Must be implemented by child contracts
     * @param amount Number of tokens to sell
     * @param minPayment Minimum acceptable payment
     */
    function sellToken(uint256 amount, uint256 minPayment) public virtual {
        revert NOT_IMPLEMENTED();
    }

    /**
     * @notice Allows owner to withdraw accumulated VRGDA surplus
     * @dev Intended for liquidity provision or grant funding
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
     * @notice Template for payment token transfer implementation
     * @dev Must be implemented by child contracts
     * @param _to Recipient address
     * @param _amount Transfer amount
     */
    function _transferPaymentWithFallback(address _to, uint256 _amount) internal virtual {}

    /**
     * @notice Validates contract upgrade authorization
     * @dev Restricts upgrades to contract owner
     * @param _newImpl New implementation contract address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
