// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { TokenEmitterETH } from "../../src/token-issuance/TokenEmitterETH.sol";
import { ERC20VotesMintable } from "../../src/ERC20VotesMintable.sol";
import { ITokenEmitter } from "../../src/interfaces/ITokenEmitter.sol";
import { ProtocolRewards } from "../../src/protocol-rewards/ProtocolRewards.sol";
import { IWETH } from "../../src/interfaces/IWETH.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { RewardPool } from "../../src/RewardPool.sol";
import { BondingSCurve } from "../../src/token-issuance/BondingSCurve.sol";
import { MockWETH } from "../mocks/MockWETH.sol";
import { console } from "forge-std/console.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { SuperfluidFrameworkDeployer } from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";

contract TokenEmitterETHTest is Test {
    // Superfluid
    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer internal deployer;
    SuperToken internal superToken;
    TestToken internal underlyingToken;

    // Contracts
    TokenEmitterETH public tokenEmitter;
    ERC20VotesMintable public erc20;
    ProtocolRewards public protocolRewards;
    MockWETH public weth;
    RewardPool public rewardPool;

    // Addresses
    address public owner;
    address public user1;
    address public user2;
    address public founderRewardAddress;
    address public protocolFeeRecipient;

    // Test Parameters
    int256 public constant CURVE_STEEPNESS = int256(1e18) / 100;
    int256 public constant BASE_PRICE = int256(1e18) / 3000;
    int256 public constant MAX_PRICE_INCREASE = int256(1e18) / 300;
    int256 public constant SUPPLY_OFFSET = int256(1e18) * 1000;
    int256 public constant PRICE_DECAY_PERCENT = int256(1e18) / 2; // 50%
    int256 public constant PER_TIME_UNIT = int256(1e18) * 500; // 500 tokens per day
    uint256 public constant FOUNDER_REWARD_DURATION = 365 days * 5; // 5 years

    function setUp() public {
        owner = makeAddr("owner");
        vm.startPrank(owner);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        founderRewardAddress = makeAddr("founderRewardAddress");
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");

        // Setup Superfluid
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
        deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();
        (underlyingToken, superToken) = deployer.deployWrapperSuperToken("Super Test Token", "STT", 18, 1e27, owner);

        // Deploy implementation contracts
        protocolRewards = new ProtocolRewards();
        TokenEmitterETH tokenEmitterImpl = new TokenEmitterETH(address(protocolRewards), protocolFeeRecipient);

        // Deploy RewardPool
        RewardPool rewardPoolImpl = new RewardPool();
        ERC1967Proxy rewardPoolProxy = new ERC1967Proxy(address(rewardPoolImpl), "");
        rewardPool = RewardPool(address(rewardPoolProxy));

        // Deploy ERC20 token
        ERC20VotesMintable erc20Impl = new ERC20VotesMintable();
        ERC1967Proxy erc20Proxy = new ERC1967Proxy(address(erc20Impl), "");
        erc20 = ERC20VotesMintable(address(erc20Proxy));

        // Deploy WETH mock
        weth = new MockWETH();

        // Deploy TokenEmitter proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(tokenEmitterImpl), "");
        tokenEmitter = TokenEmitterETH(address(proxy));

        // Initialize RewardPool
        rewardPool.initialize(ISuperToken(address(superToken)), address(erc20), address(tokenEmitter));

        // Initialize ERC20VotesMintable
        address[] memory ignoreRewardsAddresses = new address[](0);
        erc20.initialize(
            owner,
            address(tokenEmitter),
            address(rewardPool),
            ignoreRewardsAddresses,
            "Test Token",
            "TST"
        );

        // Initialize TokenEmitter
        tokenEmitter.initialize({
            _initialOwner: owner,
            _erc20: address(erc20),
            _weth: address(weth),
            _curveSteepness: CURVE_STEEPNESS,
            _basePrice: BASE_PRICE,
            _maxPriceIncrease: MAX_PRICE_INCREASE,
            _supplyOffset: SUPPLY_OFFSET,
            _priceDecayPercent: PRICE_DECAY_PERCENT,
            _perTimeUnit: PER_TIME_UNIT,
            _founderRewardAddress: founderRewardAddress,
            _founderRewardDuration: FOUNDER_REWARD_DURATION
        });

        // Set minter for ERC20
        erc20.setMinter(address(tokenEmitter));

        // Fund users with ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.stopPrank();
    }

    function getFounderReward(uint256 amount) public view returns (uint256) {
        return (amount * 7) / 100; // 7% founder reward
    }

    function testInitialization() public view {
        assertEq(address(tokenEmitter.erc20()), address(erc20), "ERC20 not set correctly");
        assertEq(address(tokenEmitter.WETH()), address(weth), "WETH not set correctly");
        assertEq(address(erc20.rewardPool()), address(rewardPool), "RewardPool not set correctly in ERC20");
        assertEq(address(rewardPool.superToken()), address(superToken), "SuperToken not set correctly in RewardPool");
        assertEq(rewardPool.manager(), address(erc20), "Manager not set correctly in RewardPool");
        assertEq(rewardPool.funder(), address(tokenEmitter), "Funder not set correctly in RewardPool");
        assertEq(tokenEmitter.curveSteepness(), CURVE_STEEPNESS, "Curve steepness not set correctly");
        assertEq(tokenEmitter.basePrice(), BASE_PRICE, "Base price not set correctly");
        assertEq(tokenEmitter.maxPriceIncrease(), MAX_PRICE_INCREASE, "Max price increase not set correctly");
        assertEq(tokenEmitter.supplyOffset(), SUPPLY_OFFSET);
    }

    function testBuyToken() public {
        uint256 amountToBuy = 500 * 1e18;
        address user = user1;

        // Start pranking as `user`
        vm.startPrank(user);

        // Get the quote for buying tokens
        (int256 costInt, ) = tokenEmitter.buyTokenQuoteWithRewards(amountToBuy);
        uint256 totalPayment = uint256(costInt);
        (int256 costWithoutRewardsInt, uint256 addedSurgeCost) = tokenEmitter.buyTokenQuote(amountToBuy);
        uint256 costWithoutRewards = uint256(costWithoutRewardsInt);
        uint256 protocolRewardsFee = totalPayment - costWithoutRewards;

        // Set maxCost higher than totalPayment to allow for some slippage
        uint256 maxCost = totalPayment + 1 ether;

        // Record initial balances
        uint256 userInitialEthBalance = user.balance;
        uint256 contractInitialEthBalance = address(tokenEmitter).balance;
        uint256 userInitialTokenBalance = erc20.balanceOf(user);

        // Call buyToken
        ITokenEmitter.ProtocolRewardAddresses memory rewardAddresses = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // Send excess ETH to test overpayment refund
        uint256 sentValue = totalPayment + 0.5 ether;

        uint256 founderReward = getFounderReward(amountToBuy);

        vm.expectEmit(true, true, true, true);
        emit ITokenEmitter.TokensBought(
            user,
            user,
            amountToBuy,
            costWithoutRewards,
            protocolRewardsFee,
            founderReward,
            addedSurgeCost
        );

        tokenEmitter.buyToken{ value: sentValue }(user, amountToBuy, maxCost, rewardAddresses);

        // Stop pranking
        vm.stopPrank();

        // Check balances after purchase
        uint256 userFinalEthBalance = user.balance;
        uint256 contractFinalEthBalance = address(tokenEmitter).balance;
        uint256 userFinalTokenBalance = erc20.balanceOf(user);

        // User ETH balance should decrease by totalPayment
        assertEq(userInitialEthBalance - userFinalEthBalance, totalPayment, "Incorrect ETH deducted");

        // Contract ETH balance should increase by totalPayment (including rewards)
        assertEq(
            contractFinalEthBalance - contractInitialEthBalance,
            uint(costWithoutRewardsInt),
            "Incorrect ETH received by contract"
        );

        // User token balance should increase by amountToBuy
        assertEq(userFinalTokenBalance - userInitialTokenBalance, amountToBuy, "Incorrect tokens minted");

        // Overpayment should be refunded
        assertEq(
            sentValue - (userInitialEthBalance - userFinalEthBalance),
            sentValue - totalPayment,
            "Overpayment not refunded"
        );
    }

    function testSellToken() public {
        uint256 amountToSell = 300 * 1e18;
        address user = user1;

        // Mint tokens to user
        vm.prank(address(tokenEmitter));
        erc20.mint(user, amountToSell);

        // Fund the contract with ETH to simulate prior buys
        vm.deal(address(tokenEmitter), 100 ether);

        // Get the quote for selling tokens
        int256 paymentInt = tokenEmitter.sellTokenQuote(amountToSell);
        uint256 payment = uint256(paymentInt);

        // Set minPayment to a value less than or equal to payment
        uint256 minPayment = payment - 1 ether;

        // Record initial balances
        uint256 userInitialEthBalance = user.balance;
        uint256 contractInitialEthBalance = address(tokenEmitter).balance;
        uint256 userInitialTokenBalance = erc20.balanceOf(user);

        vm.startPrank(user);
        vm.expectEmit(true, true, true, true);
        emit ITokenEmitter.TokensSold(user, amountToSell, payment);

        // Call sellToken
        tokenEmitter.sellToken(amountToSell, minPayment);

        vm.stopPrank();

        // Check balances after sale
        uint256 userFinalEthBalance = user.balance;
        uint256 contractFinalEthBalance = address(tokenEmitter).balance;
        uint256 userFinalTokenBalance = erc20.balanceOf(user);

        // User ETH balance should increase by payment
        assertApproxEqAbs(userFinalEthBalance - userInitialEthBalance, payment, 1e14, "Incorrect ETH received");

        // Contract ETH balance should decrease by payment
        assertEq(contractInitialEthBalance - contractFinalEthBalance, payment, "Incorrect ETH deducted from contract");

        // User token balance should decrease by amountToSell
        assertEq(userInitialTokenBalance - userFinalTokenBalance, amountToSell, "Incorrect tokens burned");
    }

    function testBuyTokenSlippageProtection() public {
        uint256 amountToBuy = 1000 * 1e18;
        address user = user1;
        vm.prank(user);

        // Get the quote for buying tokens
        (int256 costInt, uint256 addedSurgeCost) = tokenEmitter.buyTokenQuote(amountToBuy);
        uint256 cost = uint256(costInt);
        uint256 protocolRewardsFee = tokenEmitter.computeTotalReward(cost);

        uint256 totalPayment = cost + protocolRewardsFee;

        // Set maxCost less than required total payment to trigger slippage protection
        uint256 maxCost = totalPayment - 1 ether;

        // Prepare reward addresses
        ITokenEmitter.ProtocolRewardAddresses memory rewardAddresses = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // Attempt to buy tokens with insufficient maxCost
        vm.expectRevert(ITokenEmitter.SLIPPAGE_EXCEEDED.selector);
        tokenEmitter.buyToken{ value: totalPayment }(user, amountToBuy, maxCost, rewardAddresses);
    }

    function testSellTokenSlippageProtection() public {
        uint256 amountToSell = 100 * 1e18;
        address user = user1;

        // Mint tokens to user
        vm.prank(address(tokenEmitter));
        erc20.mint(user, amountToSell);

        // Fund the contract with ETH to simulate prior buys
        vm.deal(address(tokenEmitter), 50 ether);

        // Get the quote for selling tokens
        int256 paymentInt = tokenEmitter.sellTokenQuote(amountToSell);
        uint256 payment = uint256(paymentInt);

        // Set minPayment higher than actual payment to trigger slippage protection
        uint256 minPayment = payment + 1 ether;

        vm.prank(user);
        vm.expectRevert(ITokenEmitter.SLIPPAGE_EXCEEDED.selector);
        tokenEmitter.sellToken(amountToSell, minPayment);
    }

    function testBuyTokenInsufficientFunds() public {
        uint256 amountToBuy = 200 * 1e18;
        address user = user1;
        vm.prank(user);

        // Get the quote for buying tokens
        (int256 costInt, uint256 addedSurgeCost) = tokenEmitter.buyTokenQuote(amountToBuy);
        uint256 cost = uint256(costInt);
        uint256 protocolRewardsFee = tokenEmitter.computeTotalReward(cost);

        uint256 totalPayment = cost + protocolRewardsFee;

        // Prepare reward addresses
        ITokenEmitter.ProtocolRewardAddresses memory rewardAddresses = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // Attempt to buy tokens by sending less ETH than required
        vm.expectRevert(ITokenEmitter.INSUFFICIENT_FUNDS.selector);
        tokenEmitter.buyToken{ value: totalPayment - 0.5 ether }(user, amountToBuy, totalPayment, rewardAddresses);
    }

    function testSellTokenInsufficientContractBalance() public {
        uint256 amountToSell = 100 * 1e18;
        address user = user1;

        // Mint tokens to user
        vm.prank(address(tokenEmitter));
        erc20.mint(user, amountToSell);

        // Ensure contract has no ETH
        vm.deal(address(tokenEmitter), 0);

        // Attempt to sell tokens
        vm.prank(user);
        vm.expectRevert(ITokenEmitter.INSUFFICIENT_CONTRACT_BALANCE.selector);
        tokenEmitter.sellToken(amountToSell, 0);
    }

    function testOnlyOwnerCanSetMinter() public {
        // Attempt to set minter from non-owner account
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        erc20.setMinter(user1);

        // Set minter from owner account
        vm.prank(owner);
        erc20.setMinter(user1);
        assertEq(erc20.minter(), user1, "Minter not set correctly");
    }

    function testBuyTokenWithZeroAmount() public {
        // Attempt to buy zero tokens
        uint256 amountToBuy = 0;
        address user = user1;
        vm.prank(user);

        // Prepare reward addresses
        ITokenEmitter.ProtocolRewardAddresses memory rewardAddresses = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });
        // Expect revert with INVALID_AMOUNT error
        vm.expectRevert(BondingSCurve.INVALID_AMOUNT.selector);
        tokenEmitter.buyToken{ value: 0 }(user, amountToBuy, 0, rewardAddresses);

        // Verify that no tokens were minted
        assertEq(erc20.balanceOf(user), 0, "Tokens should not be minted");
    }

    function testSellTokenWithZeroAmount() public {
        // Attempt to sell zero tokens
        uint256 amountToSell = 0;
        address user = user1;

        vm.prank(user);
        // Expect revert with INVALID_AMOUNT error
        vm.expectRevert(BondingSCurve.INVALID_AMOUNT.selector);
        tokenEmitter.sellToken(amountToSell, 0);

        // Verify that no tokens were burned (balance remains zero)
        assertEq(erc20.balanceOf(user), 0, "Tokens should not be burned");
    }

    function testBuyTokenMaxAmount() public {
        uint256 amountToBuy = type(uint256).max / 1e18;
        address user = user1;
        vm.prank(user);

        // Get the quote for buying tokens
        vm.expectRevert();
        tokenEmitter.buyTokenQuote(amountToBuy);
        // Expect the function to revert due to overflow or invalid computation
    }

    function testSupplyOffsetEffect() public {
        uint256 initialSupply = erc20.totalSupply();
        uint256 amountToBuy = 500 * 1e18;

        // Buy tokens to reach supply offset
        uint256 tokensToReachOffset = uint256(SUPPLY_OFFSET) - initialSupply;

        // Buy tokens before supply offset
        (int256 costBeforeOffset, uint256 addedSurgeCostBeforeOffset) = tokenEmitter.buyTokenQuote(
            tokensToReachOffset - amountToBuy
        );
        (int256 costAtOffset, uint256 addedSurgeCostAtOffset) = tokenEmitter.buyTokenQuote(tokensToReachOffset);

        // Assert that the cost increases as we approach the supply offset
        assertTrue(costAtOffset > costBeforeOffset, "Cost should increase approaching supply offset");
    }

    function testPriceContinuity() public {
        uint256 steps = 100;
        uint256 maxAmount = 10000 * 1e18;

        int256 previousCost = 0;

        for (uint256 i = 1; i <= steps; i++) {
            uint256 amountToBuy = (maxAmount / steps) * i;
            (int256 cost, uint256 addedSurgeCost) = tokenEmitter.buyTokenQuote(amountToBuy);

            // Ensure cost increases continuously
            assertTrue(cost > previousCost, "Cost should increase continuously");
            previousCost = cost;
        }
    }

    function testBuyTokenEventEmission() public {
        uint256 amountToBuy = 100 * 1e18;
        address user = user1;
        vm.startPrank(user);

        (int256 costInt, uint256 addedSurgeCost) = tokenEmitter.buyTokenQuote(amountToBuy);
        uint256 cost = uint256(costInt);
        uint256 protocolRewardsFee = tokenEmitter.computeTotalReward(cost);
        uint256 totalPayment = cost + protocolRewardsFee;

        ITokenEmitter.ProtocolRewardAddresses memory rewardAddresses = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        uint256 founderReward = getFounderReward(amountToBuy);

        // Expect the TokensBought event
        vm.expectEmit(true, true, true, true);
        emit ITokenEmitter.TokensBought(
            user,
            user,
            amountToBuy,
            cost,
            protocolRewardsFee,
            founderReward,
            addedSurgeCost
        );

        tokenEmitter.buyToken{ value: totalPayment }(user, amountToBuy, totalPayment, rewardAddresses);
    }

    function testVRGDAPriceCap() public {
        vm.warp(block.timestamp + 1 days);
        address user = user1;

        vm.deal(user, 10000 ether);

        // Assume initial supply is less than SUPPLY_OFFSET
        uint256 initialSupply = erc20.totalSupply();
        // Account for 7% founder reward by dividing by 1.07 (since founder reward is 7% on top)
        uint256 tokensToReachVrgdaCap = ((uint256(PER_TIME_UNIT) - initialSupply) * 100) / 107;

        // Start pranking as user
        vm.startPrank(user);

        // Buy tokens below the supply offset
        ITokenEmitter.ProtocolRewardAddresses memory rewardAddresses = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        (int256 costBeforeCap, uint256 addedSurgeCostBeforeCap) = tokenEmitter.buyTokenQuote(tokensToReachVrgdaCap);
        uint256 protocolRewardsFeeBefore = tokenEmitter.computeTotalReward(uint256(costBeforeCap));
        uint256 totalPaymentBefore = uint256(costBeforeCap) + protocolRewardsFeeBefore;

        assertEq(addedSurgeCostBeforeCap, 0, "Added VRGDACap surge cost should be 0");

        uint256 founderRewardBefore = getFounderReward(tokensToReachVrgdaCap);

        vm.expectEmit(true, true, true, true);
        emit ITokenEmitter.TokensBought(
            user,
            user,
            tokensToReachVrgdaCap,
            uint256(costBeforeCap),
            protocolRewardsFeeBefore,
            founderRewardBefore,
            addedSurgeCostBeforeCap
        );

        tokenEmitter.buyToken{ value: totalPaymentBefore }(
            user,
            tokensToReachVrgdaCap,
            totalPaymentBefore,
            rewardAddresses
        );

        // Buy tokens at the supply offset to trigger VRGDACap price increase
        (int256 costAtCap, uint256 addedSurgeCostAtCap) = tokenEmitter.buyTokenQuote(tokensToReachVrgdaCap);
        uint256 protocolRewardsFeeAt = tokenEmitter.computeTotalReward(uint256(costAtCap));
        uint256 totalPaymentAt = uint256(costAtCap) + protocolRewardsFeeAt;

        assertGt(addedSurgeCostAtCap, 0, "Added VRGDACap surge cost should be > 0");

        // Assert that cost at offset is greater than cost before offset
        assertTrue(costAtCap > costBeforeCap, "Cost should increase at supply offset due to VRGDACap");

        uint256 founderRewardAt = getFounderReward(tokensToReachVrgdaCap);

        vm.expectEmit(true, true, true, true);
        emit ITokenEmitter.TokensBought(
            user,
            user,
            tokensToReachVrgdaCap,
            uint256(costAtCap),
            protocolRewardsFeeAt,
            founderRewardAt,
            addedSurgeCostAtCap
        );

        tokenEmitter.buyToken{ value: totalPaymentAt }(user, tokensToReachVrgdaCap, totalPaymentAt, rewardAddresses);

        // Additional assertions
        assertEq(
            erc20.balanceOf(user),
            tokensToReachVrgdaCap * 2,
            "User should have bought tokens up to supply offset"
        );

        vm.stopPrank();

        // Advance the blockchain time by 3 days
        vm.warp(block.timestamp + 3 days);

        // Buy additional tokens after waiting
        (int256 costAfterWait, uint256 surgeCostAfterWait) = tokenEmitter.buyTokenQuote(tokensToReachVrgdaCap);
        uint256 protocolRewardsFeeAfterWait = tokenEmitter.computeTotalReward(uint256(costAfterWait));
        uint256 totalPaymentAfterWait = uint256(costAfterWait) + protocolRewardsFeeAfterWait;

        assertEq(surgeCostAfterWait, 0, "Added VRGDACap surge cost should be = 0");

        uint256 founderRewardAfterWait = getFounderReward(tokensToReachVrgdaCap);

        vm.expectEmit(true, true, true, true);
        emit ITokenEmitter.TokensBought(
            user,
            user,
            tokensToReachVrgdaCap,
            uint256(costAfterWait),
            protocolRewardsFeeAfterWait,
            founderRewardAfterWait,
            surgeCostAfterWait
        );

        vm.prank(user);
        tokenEmitter.buyToken{ value: totalPaymentAfterWait }(
            user,
            tokensToReachVrgdaCap,
            totalPaymentAfterWait,
            rewardAddresses
        );

        uint256 balanceBeforeWithdraw = address(tokenEmitter.owner()).balance;

        // Withdraw the extra VRGDA Payment
        vm.prank(owner);
        tokenEmitter.withdrawVRGDAPayment();

        uint256 balanceAfterWithdraw = address(tokenEmitter.owner()).balance;

        uint256 totalOwnerPayment = surgeCostAfterWait + addedSurgeCostAtCap + addedSurgeCostBeforeCap;

        assertEq(balanceAfterWithdraw - balanceBeforeWithdraw, totalOwnerPayment, "Owner should have received ETH");

        uint256 largePurchase = tokensToReachVrgdaCap * 6;

        // Buy more tokens after withdrawing
        (int256 costMore, uint256 surgeCostMore) = tokenEmitter.buyTokenQuote(largePurchase);
        uint256 protocolRewardsFeeMore = tokenEmitter.computeTotalReward(uint256(costMore));
        uint256 totalPaymentMore = uint256(costMore) + protocolRewardsFeeMore;

        uint256 founderRewardMore = getFounderReward(largePurchase);

        vm.expectEmit(true, true, true, true);
        emit ITokenEmitter.TokensBought(
            user,
            user,
            largePurchase,
            uint256(costMore),
            protocolRewardsFeeMore,
            founderRewardMore,
            surgeCostMore
        );

        vm.prank(user);
        tokenEmitter.buyToken{ value: totalPaymentMore }(user, largePurchase, totalPaymentMore, rewardAddresses);

        // Sell all tokens back
        uint256 totalTokens = tokenEmitter.erc20().balanceOf(user);
        uint256 minPayment = 1; // Set appropriate minimum payment
        vm.prank(user);
        tokenEmitter.sellToken(totalTokens, minPayment);

        balanceBeforeWithdraw = address(tokenEmitter.owner()).balance;

        // have the founder sell back their tokens
        vm.startPrank(founderRewardAddress);
        tokenEmitter.sellToken(erc20.balanceOf(founderRewardAddress), 0);
        vm.stopPrank();

        // Withdraw the final VRGDA Payment
        vm.prank(owner);
        tokenEmitter.withdrawVRGDAPayment();

        balanceAfterWithdraw = address(tokenEmitter.owner()).balance;

        assertEq(balanceAfterWithdraw - balanceBeforeWithdraw, surgeCostMore, "Owner should have received ETH");

        // some left over is expected due to overcharging on purchases by 1 wei to avoid precision loss
        assertApproxEqAbs(address(tokenEmitter).balance, 0, 10, "ETH balance should be basically 0");
    }

    function testFounderRewards() public {
        uint256 amountToBuy = 100 * 1e18;
        address user = user1;
        vm.startPrank(user);

        // Get quote and prepare purchase
        (int256 costInt, uint256 addedSurgeCost) = tokenEmitter.buyTokenQuote(amountToBuy);
        uint256 cost = uint256(costInt);
        uint256 protocolRewardsFee = tokenEmitter.computeTotalReward(cost);
        uint256 totalPayment = cost + protocolRewardsFee;

        ITokenEmitter.ProtocolRewardAddresses memory rewardAddresses = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // Check initial balances
        uint256 initialFounderBalance = erc20.balanceOf(founderRewardAddress);
        uint256 initialUserBalance = erc20.balanceOf(user);

        // Buy tokens
        tokenEmitter.buyToken{ value: totalPayment }(user, amountToBuy, totalPayment, rewardAddresses);

        // Check balances after purchase
        uint256 expectedFounderReward = (amountToBuy * 7) / 100; // 7% founder reward
        uint256 finalFounderBalance = erc20.balanceOf(founderRewardAddress);
        uint256 finalUserBalance = erc20.balanceOf(user);

        // Verify balances
        assertEq(finalFounderBalance - initialFounderBalance, expectedFounderReward, "Incorrect founder reward amount");
        assertEq(finalUserBalance - initialUserBalance, amountToBuy, "Incorrect user token amount");

        // Test small purchase (less than 10 wei in tokens)
        uint256 smallAmount = 5;
        (costInt, addedSurgeCost) = tokenEmitter.buyTokenQuote(smallAmount);
        cost = uint256(costInt);
        protocolRewardsFee = tokenEmitter.computeTotalReward(cost);
        totalPayment = cost + protocolRewardsFee;

        initialFounderBalance = erc20.balanceOf(founderRewardAddress);
        initialUserBalance = erc20.balanceOf(user);

        // Buy small amount of tokens
        tokenEmitter.buyToken{ value: totalPayment }(user, smallAmount, totalPayment, rewardAddresses);

        // For small purchases (< 10 tokens), founder reward should be 1
        finalFounderBalance = erc20.balanceOf(founderRewardAddress);
        finalUserBalance = erc20.balanceOf(user);

        assertEq(finalFounderBalance - initialFounderBalance, 1, "Incorrect founder reward for small purchase");
        assertEq(finalUserBalance - initialUserBalance, smallAmount, "Incorrect user token amount for small purchase");

        vm.stopPrank();

        // Test after founder reward expiration
        vm.warp(block.timestamp + FOUNDER_REWARD_DURATION + 1);

        vm.prank(user);
        (costInt, addedSurgeCost) = tokenEmitter.buyTokenQuote(amountToBuy);
        cost = uint256(costInt);
        protocolRewardsFee = tokenEmitter.computeTotalReward(cost);
        totalPayment = cost + protocolRewardsFee;

        initialFounderBalance = erc20.balanceOf(founderRewardAddress);

        vm.prank(user);
        tokenEmitter.buyToken{ value: totalPayment }(user, amountToBuy, totalPayment, rewardAddresses);

        finalFounderBalance = erc20.balanceOf(founderRewardAddress);

        // No founder reward should be minted after expiration
        assertEq(finalFounderBalance, initialFounderBalance, "Founder should not receive rewards after expiration");
    }

    function testFounderRewardWithZeroAddress() public {
        // Deploy new token emitter with zero founder reward address
        TokenEmitterETH tokenEmitterImpl = new TokenEmitterETH(address(protocolRewards), protocolFeeRecipient);
        ERC1967Proxy proxy = new ERC1967Proxy(address(tokenEmitterImpl), "");
        TokenEmitterETH newTokenEmitter = TokenEmitterETH(address(proxy));

        // Initialize with zero address for founder rewards
        vm.startPrank(owner);
        newTokenEmitter.initialize({
            _initialOwner: owner,
            _erc20: address(erc20),
            _weth: address(weth),
            _curveSteepness: CURVE_STEEPNESS,
            _basePrice: BASE_PRICE,
            _maxPriceIncrease: MAX_PRICE_INCREASE,
            _supplyOffset: SUPPLY_OFFSET,
            _priceDecayPercent: PRICE_DECAY_PERCENT,
            _perTimeUnit: PER_TIME_UNIT,
            _founderRewardAddress: address(0),
            _founderRewardDuration: FOUNDER_REWARD_DURATION
        });
        vm.stopPrank();

        // Set minter
        vm.prank(owner);
        erc20.setMinter(address(newTokenEmitter));

        uint256 amountToBuy = 100 * 1e18;
        address user = user1;
        vm.startPrank(user);

        // Get quote and prepare purchase
        (int256 costInt, uint256 addedSurgeCost) = newTokenEmitter.buyTokenQuote(amountToBuy);
        uint256 cost = uint256(costInt);
        uint256 protocolRewardsFee = newTokenEmitter.computeTotalReward(cost);
        uint256 totalPayment = cost + protocolRewardsFee;

        ITokenEmitter.ProtocolRewardAddresses memory rewardAddresses = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        uint256 initialSupply = erc20.totalSupply();

        // Buy tokens
        newTokenEmitter.buyToken{ value: totalPayment }(user, amountToBuy, totalPayment, rewardAddresses);

        // Verify only user tokens were minted (no founder rewards)
        assertEq(erc20.totalSupply() - initialSupply, amountToBuy, "Only user tokens should be minted");
    }

    function testRepeatedPartialSell() public {
        address user = user1;
        uint256 totalMint = 1000 * 1e18;
        vm.startPrank(address(tokenEmitter));
        erc20.mint(user, totalMint); // mimic a user who has 1000 tokens
        vm.stopPrank();

        // Fund contract with ETH so sells can succeed
        vm.deal(address(tokenEmitter), 300 ether);

        uint256 userInitialBal = user.balance;

        // Sell in multiple parts
        uint256 part1 = 300 * 1e18;
        uint256 part2 = 200 * 1e18;
        uint256 part3 = 500 * 1e18; // the remainder

        // For each part, we get a quote and sell
        // PART 1
        int256 paymentInt1 = tokenEmitter.sellTokenQuote(part1);
        uint256 expectedPay1 = uint256(paymentInt1);

        vm.prank(user);
        tokenEmitter.sellToken(part1, 0); // accept any payment >= 0

        // PART 2
        int256 paymentInt2 = tokenEmitter.sellTokenQuote(part2);
        uint256 expectedPay2 = uint256(paymentInt2);

        vm.prank(user);
        tokenEmitter.sellToken(part2, 0);

        // PART 3
        int256 paymentInt3 = tokenEmitter.sellTokenQuote(part3);
        uint256 expectedPay3 = uint256(paymentInt3);

        vm.prank(user);
        tokenEmitter.sellToken(part3, 0);

        // Final checks
        uint256 userFinalBal = user.balance;

        // The sum of each partial pay
        uint256 totalExpected = expectedPay1 + expectedPay2 + expectedPay3;
        // The user should have gained about that much total
        assertApproxEqAbs(
            userFinalBal - userInitialBal,
            totalExpected,
            1e14, // tolerance
            "User didn't receive the correct total from partial sells"
        );

        // Check user tokens are fully burned
        assertEq(erc20.balanceOf(user), 0, "User should have sold all tokens");
    }

    function testReinitializeShouldFail() public {
        // First initialization is done in setUp(), so let's confirm a second fails
        vm.startPrank(owner);

        // Attempt to call initialize again
        vm.expectRevert("Initializable: contract is already initialized");
        tokenEmitter.initialize({
            _initialOwner: owner,
            _erc20: address(erc20),
            _weth: address(weth),
            _curveSteepness: CURVE_STEEPNESS,
            _basePrice: BASE_PRICE,
            _maxPriceIncrease: MAX_PRICE_INCREASE,
            _supplyOffset: SUPPLY_OFFSET,
            _priceDecayPercent: PRICE_DECAY_PERCENT,
            _perTimeUnit: PER_TIME_UNIT,
            _founderRewardAddress: founderRewardAddress,
            _founderRewardDuration: FOUNDER_REWARD_DURATION
        });

        vm.stopPrank();
    }

    function testLockMinterCannotUpdateAgain() public {
        // Make sure we're the owner
        vm.startPrank(owner);

        // Initially set a new minter
        erc20.setMinter(makeAddr("initialMinter"));
        assertEq(erc20.minter(), makeAddr("initialMinter"));

        // Now lock the minter
        erc20.lockMinter();

        // Attempt to change minter again
        vm.expectRevert(abi.encodeWithSignature("MINTER_LOCKED()"));
        erc20.setMinter(makeAddr("secondMinter"));

        vm.stopPrank();
    }

    function testProtocolRewardsSplit() public {
        // We'll pick some non-zero addresses for builder & referral
        address builderAddr = makeAddr("builder");
        address referralAddr = makeAddr("referral");

        // We'll buy an amount of tokens
        uint256 amountToBuy = 200 * 1e18;
        address user = user1;
        vm.deal(user, 50 ether); // ensure user has enough ETH

        // Prepare the protocol reward addresses
        ITokenEmitter.ProtocolRewardAddresses memory rewardAddresses = ITokenEmitter.ProtocolRewardAddresses({
            builder: builderAddr,
            purchaseReferral: referralAddr
        });

        // Get buy quote
        vm.prank(user);
        (int256 costInt, ) = tokenEmitter.buyTokenQuote(amountToBuy);
        uint256 costForTokens = uint256(costInt);

        // Calculate protocol rewards and total payment
        uint256 protocolRewardsFee = tokenEmitter.computeTotalReward(costForTokens);
        uint256 totalPayment = costForTokens + protocolRewardsFee;

        // Calculate expected rewards based on costForTokens
        uint256 expectedBuilderReward = (costForTokens * 100) / 10_000; // 1.0% BUILDER_REWARD_BPS
        uint256 expectedReferralReward = (costForTokens * 50) / 10_000; // 0.5% PURCHASE_REFERRAL_BPS

        // We send a bit more to handle any rounding
        uint256 sentValue = totalPayment + 0.1 ether;

        // Record balances before
        uint256 builderInitialBal = protocolRewards.balanceOf(builderAddr);
        uint256 referralInitialBal = protocolRewards.balanceOf(referralAddr);

        // Actually buy the tokens
        vm.prank(user);
        tokenEmitter.buyToken{ value: sentValue }(
            user,
            amountToBuy,
            totalPayment, // maxCost = totalPayment
            rewardAddresses
        );

        // Check balances after
        uint256 builderFinalBal = protocolRewards.balanceOf(builderAddr);
        uint256 referralFinalBal = protocolRewards.balanceOf(referralAddr);

        // They should have increased balances in the ProtocolRewards contract
        assertTrue(builderFinalBal > builderInitialBal, "Builder did not receive protocol rewards");
        assertTrue(referralFinalBal > referralInitialBal, "Referral did not receive protocol rewards");

        // Verify the rewards were deposited correctly
        uint256 builderIncrease = builderFinalBal - builderInitialBal;
        uint256 referralIncrease = referralFinalBal - referralInitialBal;

        // Check that rewards match expected BPS splits from RewardSplits
        assertEq(builderIncrease, expectedBuilderReward, "Builder reward incorrect");
        assertEq(referralIncrease, expectedReferralReward, "Referral reward incorrect");
    }
}
