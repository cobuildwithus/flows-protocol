// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { BondingSCurve } from "./token-issuance/BondingSCurve.sol";
import { VRGDACap } from "./token-issuance/VRGDACap.sol";
import { ERC20VotesMintable } from "./ERC20VotesMintable.sol";
import { ITokenEmitter } from "./interfaces/ITokenEmitter.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { FlowProtocolRewards } from "./protocol-rewards/abstract/FlowProtocolRewards.sol";
import { toDaysWadUnsafe, wadDiv } from "./libs/SignedWadMath.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title TokenEmitter
 * @dev Contract for emitting tokens using a bonding curve mechanism
 */
contract TokenEmitter is
    ITokenEmitter,
    BondingSCurve,
    VRGDACap,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    FlowProtocolRewards
{
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

    // The extra ETH received from high VRGDACap prices
    uint256 public vrgdaCapExtraETH;

    ///                                                          ///
    ///                           ERRORS                         ///
    ///                                                          ///

    /// @notice Reverts for address zero
    error INVALID_ADDRESS_ZERO();

    /**
     * @param _protocolRewards The protocol rewards contract address
     * @param _protocolFeeRecipient The protocol fee recipient address
     */
    constructor(
        address _protocolRewards,
        address _protocolFeeRecipient
    ) payable FlowProtocolRewards(_protocolRewards, _protocolFeeRecipient) initializer {
        if (_protocolRewards == address(0)) revert ADDRESS_ZERO();
        if (_protocolFeeRecipient == address(0)) revert ADDRESS_ZERO();
    }

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
    ) public initializer {
        if (_erc20 == address(0)) revert INVALID_ADDRESS_ZERO();
        if (_weth == address(0)) revert INVALID_ADDRESS_ZERO();
        if (_initialOwner == address(0)) revert INVALID_ADDRESS_ZERO();

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
     * @return addedSurgeCost The extra ETH paid by users due to high VRGDACap prices
     * @dev Uses the bonding curve to determine the minimum cost, but if sales are ahead of schedule, the VRGDACap price will be used
     */
    function buyTokenQuote(uint256 amount) public view returns (int256 totalCost, uint256 addedSurgeCost) {
        if (amount == 0) revert INVALID_AMOUNT();

        uint256 founderReward = calculateFounderReward(amount);
        bool isFounderRewardActive = isFounderRewardActive();

        uint256 totalMintAmount = amount + (isFounderRewardActive ? founderReward : 0);

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
     * @notice Calculates the cost to buy a certain amount of tokens including protocol rewards
     * @dev Uses the bonding curve to determine the cost
     * @param amount The number of tokens to buy
     * @return totalCost The cost to buy the specified amount of tokens including protocol rewards
     * @return addedSurgeCost The extra ETH paid by users due to high VRGDACap prices
     */
    function buyTokenQuoteWithRewards(uint256 amount) public view returns (int256 totalCost, uint256 addedSurgeCost) {
        (int256 costInt, uint256 surgeCost) = buyTokenQuote(amount);
        if (costInt < 0) revert INVALID_COST();

        totalCost = costInt + int256(computeTotalReward(uint256(costInt)));
        addedSurgeCost = surgeCost;
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
     * @notice Allows users to buy tokens by sending ETH with slippage protection
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
    ) public payable nonReentrant {
        if (user == address(0)) revert INVALID_ADDRESS_ZERO();
        if (amount == 0) revert INVALID_AMOUNT();

        (int256 costInt, uint256 surgeCost) = buyTokenQuote(amount);
        if (costInt < 0) revert INVALID_COST();
        uint256 costForTokens = uint256(costInt);

        if (costForTokens > maxCost) revert SLIPPAGE_EXCEEDED();

        uint256 protocolRewardsFee = computeTotalReward(costForTokens);
        uint256 totalPayment = costForTokens + protocolRewardsFee;

        // Check for underpayment
        if (msg.value < totalPayment) revert INSUFFICIENT_FUNDS();

        // Handle overpayment
        if (msg.value > totalPayment) {
            _safeTransferETHWithFallback(_msgSender(), msg.value - totalPayment);
        }

        // Share protocol rewards
        _handleRewardsAndGetValueToSend(
            costForTokens, // pass in cost before rewards
            protocolRewardsRecipients.builder,
            protocolRewardsRecipients.purchaseReferral
        );

        if (surgeCost > 0) {
            vrgdaCapExtraETH += surgeCost;
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
     * @notice Calculates the founder reward for a given amount of tokens
     * @param amount The number of tokens to buy
     * @return The amount of founder reward tokens to mint
     */
    function calculateFounderReward(uint256 amount) public view returns (uint256) {
        return amount >= 10 ? (amount * 10) / 100 : 1;
    }

    /**
     * @notice Checks if the founder reward is active
     * @return True if the founder reward is active, false otherwise
     */
    function isFounderRewardActive() public view returns (bool) {
        return founderRewardAddress != address(0) && block.timestamp < founderRewardExpiration;
    }

    /**
     * @notice Allows users to sell tokens and receive ETH with slippage protection.
     * @dev Only pays back an amount of ETH that fits on the bonding curve, does not factor in VRGDACap extra ETH.
     * @param amount The number of tokens to sell
     * @param minPayment The minimum acceptable payment in wei
     */
    function sellToken(uint256 amount, uint256 minPayment) public nonReentrant {
        int256 paymentInt = sellTokenQuote(amount);
        if (paymentInt < 0) revert INVALID_PAYMENT();
        if (amount == 0) revert INVALID_AMOUNT();
        uint256 payment = uint256(paymentInt);

        if (payment < minPayment) revert SLIPPAGE_EXCEEDED();
        if (payment > address(this).balance) revert INSUFFICIENT_CONTRACT_BALANCE();
        if (erc20.balanceOf(_msgSender()) < amount) revert INSUFFICIENT_TOKEN_BALANCE();

        erc20.burn(_msgSender(), amount);

        _safeTransferETHWithFallback(_msgSender(), payment);

        emit TokensSold(_msgSender(), amount, payment);
    }

    /**
     * @notice Allows the owner to withdraw accumulated VRGDACap ETH
     * @dev Plan is to use this to fund a liquidity pool OR fund the Flow grantees for this token
     */
    function withdrawVRGDAETH() external onlyOwner {
        uint256 amount = vrgdaCapExtraETH;
        if (amount > 0) {
            vrgdaCapExtraETH = 0;
            emit VRGDACapETHWithdrawn(amount);
            _safeTransferETHWithFallback(owner(), amount);
        }
    }

    /**
     * @notice Transfer ETH/WETH from the contract
     * @dev Attempts to transfer ETH first, falls back to WETH if ETH transfer fails
     * @param _to The recipient address
     * @param _amount The amount transferring
     */
    function _safeTransferETHWithFallback(address _to, uint256 _amount) private {
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

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
