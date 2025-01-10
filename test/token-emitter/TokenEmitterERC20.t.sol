// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { TokenEmitterERC20 } from "../../src/token-issuance/TokenEmitterERC20.sol";
import { ERC20VotesMintable } from "../../src/ERC20VotesMintable.sol";
import { ITokenEmitter } from "../../src/interfaces/ITokenEmitter.sol";
import { ProtocolRewards } from "../../src/protocol-rewards/ProtocolRewards.sol";
import { IWETH } from "../../src/interfaces/IWETH.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { RewardPool } from "../../src/RewardPool.sol";
import { BondingSCurve } from "../../src/token-issuance/BondingSCurve.sol";
import { MockWETH } from "../mocks/MockWETH.sol";

import { SuperfluidFrameworkDeployer } from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";

contract TokenEmitterERC20Test is Test {
    // Payment token, used by the Emitter
    ERC20VotesMintable public paymentToken;

    // The ERC20 token we are emitting (the "governance token" or "brand token")
    ERC20VotesMintable public erc20;

    // WETH mock
    MockWETH public weth;

    // Our Emitter logic contract
    TokenEmitterERC20 public tokenEmitter;

    // Protocol rewards
    ProtocolRewards public protocolRewards;
    RewardPool public rewardPool;
    RewardPool public paymentTokenRewardPool;

    // Some addresses
    address public owner;
    address public user1;
    address public user2;
    address public founderRewardAddress;
    address public protocolFeeRecipient;

    // Superfluid references if you need them
    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer internal deployer;
    SuperToken internal superToken;
    TestToken internal underlyingToken;

    // Bonding curve / VRGDACap parameters
    int256 public constant CURVE_STEEPNESS = int256(1e18) / 100;
    int256 public constant BASE_PRICE = int256(1e18) / 3000;
    int256 public constant MAX_PRICE_INCREASE = int256(1e18) / 300;
    int256 public constant SUPPLY_OFFSET = int256(1e18) * 1000;
    int256 public constant PRICE_DECAY_PERCENT = int256(1e18) / 2; // 50%
    int256 public constant PER_TIME_UNIT = int256(1e18) * 500; // 500 tokens/day
    uint256 public constant FOUNDER_REWARD_DURATION = 365 days * 5; // 5 years

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        founderRewardAddress = makeAddr("founderRewardAddress");
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");

        // We do everything as "owner" initially
        vm.startPrank(owner);

        // 1) Deploy a Payment Token (ERC20VotesMintable) with proxy
        ERC20VotesMintable paymentTokenImpl = new ERC20VotesMintable();
        ERC1967Proxy paymentTokenProxy = new ERC1967Proxy(address(paymentTokenImpl), "");
        address[] memory ignoreRewardsAddresses = new address[](0);
        paymentToken = ERC20VotesMintable(address(paymentTokenProxy));

        // 2) Deploy the ProtocolRewards
        protocolRewards = new ProtocolRewards();

        // 3) Deploy the RewardPools
        RewardPool rewardPoolImpl = new RewardPool();
        ERC1967Proxy rewardPoolProxy = new ERC1967Proxy(address(rewardPoolImpl), "");
        rewardPool = RewardPool(address(rewardPoolProxy));

        RewardPool paymentTokenRewardPoolImpl = new RewardPool();
        ERC1967Proxy paymentTokenRewardPoolProxy = new ERC1967Proxy(address(paymentTokenRewardPoolImpl), "");
        paymentTokenRewardPool = RewardPool(address(paymentTokenRewardPoolProxy));

        // 4) Deploy the main minted token (the brand token)
        ERC20VotesMintable erc20Impl = new ERC20VotesMintable();
        ERC1967Proxy erc20Proxy = new ERC1967Proxy(address(erc20Impl), "");
        erc20 = ERC20VotesMintable(address(erc20Proxy));

        // 5) Deploy the Emitter Implementation
        TokenEmitterERC20 tokenEmitterImpl = new TokenEmitterERC20(address(protocolRewards), protocolFeeRecipient);

        // 6) Deploy Emitter Proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(tokenEmitterImpl), "");
        tokenEmitter = TokenEmitterERC20(address(proxy));

        // Deploy WETH mock
        weth = new MockWETH();

        // Setup Superfluid
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
        deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();
        (underlyingToken, superToken) = deployer.deployWrapperSuperToken("Super Test Token", "STT", 18, 1e27, owner);

        // Initialize reward pools
        rewardPool.initialize(superToken, address(erc20), address(tokenEmitter));
        paymentTokenRewardPool.initialize(superToken, address(paymentToken), address(tokenEmitter));

        // 8) Initialize ERC20VotesMintable
        erc20.initialize(
            owner,
            address(tokenEmitter),
            address(rewardPool),
            ignoreRewardsAddresses,
            "Test Brand Token",
            "BRAND"
        );

        paymentToken.initialize(
            owner,
            address(this),
            address(paymentTokenRewardPool),
            ignoreRewardsAddresses,
            "Test Token",
            "TST"
        );

        // 9) Initialize the Emitter (the child)
        tokenEmitter.initialize(
            owner,
            address(erc20),
            address(weth),
            founderRewardAddress,
            CURVE_STEEPNESS,
            BASE_PRICE,
            MAX_PRICE_INCREASE,
            SUPPLY_OFFSET,
            PRICE_DECAY_PERCENT,
            PER_TIME_UNIT,
            FOUNDER_REWARD_DURATION,
            address(paymentToken)
        );

        // 10) Set the Emitter as minter for the ERC20 brand token
        erc20.setMinter(address(tokenEmitter));

        // 12) Stop acting as "owner"
        vm.stopPrank();

        // 11) Fund user1, user2 with "paymentToken" balance
        paymentToken.mint(user1, 10_000e18); // 10k tokens
        paymentToken.mint(user2, 10_000e18);
    }

    // Helper function if you want to replicate the code for founder reward
    function getFounderReward(uint256 amount) public pure returns (uint256) {
        // The code in Emitter says: 7% if >=14, else 1
        if (amount >= 14) {
            return (amount * 7) / 100;
        } else {
            return 1;
        }
    }

    // 1) test initialization
    function testInitialization() public {
        assertEq(address(tokenEmitter.erc20()), address(erc20), "ERC20 not set correctly");
        assertEq(address(tokenEmitter.paymentToken()), address(paymentToken), "paymentToken not set correctly");
        assertEq(address(erc20.minter()), address(tokenEmitter), "Minter not set to tokenEmitter");
        // Add more checks if you wish
    }

    // 2) test buy token
    function testBuyToken() public {
        // We'll buy e.g. 500 tokens
        uint256 amountToBuy = 500 * 1e18;
        address user = user1;

        vm.startPrank(user);

        // Approve the emitter to spend user's paymentToken
        paymentToken.approve(address(tokenEmitter), type(uint256).max);

        // Quote cost
        (int256 costInt, uint256 surgeCost) = tokenEmitter.buyTokenQuote(amountToBuy);
        uint256 costForTokens = uint256(costInt);
        uint256 protocolFee = tokenEmitter.computeTotalReward(costForTokens);
        uint256 totalPayment = costForTokens + protocolFee;

        // We'll allow some "maxCost" = totalPayment + some buffer
        uint256 maxCost = totalPayment + 1e18;

        // Check initial balances
        uint256 userPaymentBalanceBefore = paymentToken.balanceOf(user);
        uint256 contractPaymentBalanceBefore = paymentToken.balanceOf(address(tokenEmitter));
        uint256 userTokenBalanceBefore = erc20.balanceOf(user);

        // Call buyToken
        ITokenEmitter.ProtocolRewardAddresses memory rewardAddrs = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        tokenEmitter.buyToken(user, amountToBuy, maxCost, rewardAddrs);

        vm.stopPrank();

        // Check final balances
        uint256 userPaymentBalanceAfter = paymentToken.balanceOf(user);
        uint256 contractPaymentBalanceAfter = paymentToken.balanceOf(address(tokenEmitter));
        uint256 userTokenBalanceAfter = erc20.balanceOf(user);

        // user should have paid exactly totalPayment
        assertEq(
            userPaymentBalanceBefore - userPaymentBalanceAfter,
            totalPayment,
            "User didn't pay correct totalPayment"
        );

        // contract should have gained totalPayment
        assertEq(
            contractPaymentBalanceAfter - contractPaymentBalanceBefore,
            totalPayment,
            "Contract didn't receive correct totalPayment"
        );

        // user brand token balance should + amountToBuy
        assertEq(userTokenBalanceAfter - userTokenBalanceBefore, amountToBuy, "Incorrect minted brand tokens for user");
    }

    // 3) test slippage for buy
    function testBuyTokenSlippageProtection() public {
        address user = user1;

        vm.startPrank(user);

        paymentToken.approve(address(tokenEmitter), type(uint256).max);

        uint256 amountToBuy = 1000 * 1e18;
        (int256 costInt, ) = tokenEmitter.buyTokenQuote(amountToBuy);
        uint256 cost = uint256(costInt);
        uint256 fee = tokenEmitter.computeTotalReward(cost);
        uint256 totalPayment = cost + fee;

        // Set maxCost to something smaller
        uint256 maxCost = totalPayment - 1e18;

        ITokenEmitter.ProtocolRewardAddresses memory rewardAddrs = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // Expect revert on slippage
        vm.expectRevert(ITokenEmitter.SLIPPAGE_EXCEEDED.selector);
        tokenEmitter.buyToken(user, amountToBuy, maxCost, rewardAddrs);

        vm.stopPrank();
    }

    // 4) test buy token zero amount
    function testBuyTokenZeroAmount() public {
        address user = user1;
        vm.startPrank(user);
        paymentToken.approve(address(tokenEmitter), type(uint256).max);

        ITokenEmitter.ProtocolRewardAddresses memory rewardAddrs = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // Expect revert with INVALID_AMOUNT
        vm.expectRevert(BondingSCurve.INVALID_AMOUNT.selector);
        tokenEmitter.buyToken(user, 0, 1e18, rewardAddrs);

        vm.stopPrank();
    }

    // 5) test user doesn't have enough payment tokens
    function testBuyTokenInsufficientFunds() public {
        address user = user1;
        vm.startPrank(user);

        // We'll not give them enough tokens or we'll not approve enough
        paymentToken.approve(address(tokenEmitter), 10e18);

        uint256 amountToBuy = 5000 * 1e18;
        (int256 costInt, ) = tokenEmitter.buyTokenQuote(amountToBuy);
        uint256 costForTokens = uint256(costInt);
        uint256 totalPayment = costForTokens + tokenEmitter.computeTotalReward(costForTokens);

        ITokenEmitter.ProtocolRewardAddresses memory rewardAddrs = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        vm.expectRevert(ITokenEmitter.INSUFFICIENT_FUNDS.selector);
        tokenEmitter.buyToken(user, amountToBuy, totalPayment, rewardAddrs);

        vm.stopPrank();
    }

    // 6) test sell token
    function testSellToken() public {
        address user = user1;

        // we first buy tokens to have some brand tokens
        _buySomeTokens(user, 1000e18);

        // now the contract has some payment tokens from that purchase
        // let's do a partial sell
        uint256 amountToSell = 300e18;

        // get the sell quote
        int256 paymentInt = tokenEmitter.sellTokenQuote(amountToSell);
        uint256 expectedPay = uint256(paymentInt);

        // optionally do a minPayment check
        uint256 minPayment = expectedPay - 1e18; // allow 1e18 slippage

        // check initial balances
        uint256 userTokenBefore = erc20.balanceOf(user);
        uint256 userPayBefore = paymentToken.balanceOf(user);
        uint256 contractPayBefore = paymentToken.balanceOf(address(tokenEmitter));

        vm.startPrank(user);
        tokenEmitter.sellToken(amountToSell, minPayment);
        vm.stopPrank();

        // check final
        uint256 userTokenAfter = erc20.balanceOf(user);
        uint256 userPayAfter = paymentToken.balanceOf(user);
        uint256 contractPayAfter = paymentToken.balanceOf(address(tokenEmitter));

        // user brand tokens should decrease by 300
        assertEq(userTokenBefore - userTokenAfter, amountToSell, "user brand token not burned properly");

        // user payment tokens should increase by expectedPay
        assertEq(userPayAfter - userPayBefore, expectedPay, "user didn't get correct pay tokens");

        // contract payment tokens should decrease by expectedPay
        assertEq(contractPayBefore - contractPayAfter, expectedPay, "contract didn't pay out correct payment tokens");
    }

    // 7) test sell token zero amount
    function testSellTokenZeroAmount() public {
        address user = user1;

        vm.startPrank(user);
        // expect revert with INVALID_AMOUNT
        vm.expectRevert(BondingSCurve.INVALID_AMOUNT.selector);
        tokenEmitter.sellToken(0, 0);

        vm.stopPrank();
    }

    // 8) test sell token slippage
    function testSellTokenSlippageProtection() public {
        address user = user1;

        // buy some tokens for user
        _buySomeTokens(user, 1000e18);

        // let's get quote
        int256 paymentInt = tokenEmitter.sellTokenQuote(500e18);
        uint256 pay = uint256(paymentInt);

        // set minPayment to be bigger than actual
        uint256 minPayment = pay + 1e18;

        vm.startPrank(user);
        vm.expectRevert(ITokenEmitter.SLIPPAGE_EXCEEDED.selector);
        tokenEmitter.sellToken(500e18, minPayment);

        vm.stopPrank();
    }

    // 9) test insufficient contract payment token
    function testSellTokenInsufficientContractBalance() public {
        address user = user1;
        // user has brand tokens, but let's not do a buy so the contract doesn't have enough payment tokens
        // or we forcibly remove them from contract?

        // We'll do the scenario:
        // a) user has minted brand tokens
        vm.prank(address(tokenEmitter));
        erc20.mint(user, 1000e18);

        // b) contract has 0 payment tokens
        // so the user can't be paid out
        vm.startPrank(user);
        // get quote
        int256 paymentInt = tokenEmitter.sellTokenQuote(1000e18);
        uint256 pay = uint256(paymentInt);

        // expect revert
        vm.expectRevert(ITokenEmitter.INSUFFICIENT_CONTRACT_BALANCE.selector);
        tokenEmitter.sellToken(1000e18, 0);

        vm.stopPrank();
    }

    // 10) test partial repeated sells
    function testPartialRepeatedSells() public {
        address user = user1;

        // buy some tokens so the contract has payment tokens
        _buySomeTokens(user, 1000e18);

        // do repeated sells
        uint256 firstSell = 400e18;
        uint256 secondSell = 200e18;
        uint256 thirdSell = 400e18; // total 1000

        uint256 userPayBefore = paymentToken.balanceOf(user);
        uint256 userTokBefore = erc20.balanceOf(user);

        // 1st
        vm.prank(user);
        tokenEmitter.sellToken(firstSell, 0);

        // 2nd
        vm.prank(user);
        tokenEmitter.sellToken(secondSell, 0);

        // 3rd
        vm.prank(user);
        tokenEmitter.sellToken(thirdSell, 0);

        uint256 userPayAfter = paymentToken.balanceOf(user);
        uint256 userTokAfter = erc20.balanceOf(user);

        // user tokens: 1000 burned
        assertEq(userTokBefore - userTokAfter, 1000e18, "User didn't sell the correct total tokens");
        // user pay tokens: sum of the three quotes
        // for thoroughness, we can sum the quotes ourselves. We'll rely on final difference check with ~0.
        // But let's just do a sanity check that user got more than 0

        assertTrue(userPayAfter > userPayBefore, "User didn't receive any payment tokens");
    }

    // 11) test founder rewards
    function testFounderRewards() public {
        address user = user1;
        vm.startPrank(user);

        paymentToken.approve(address(tokenEmitter), type(uint256).max);

        // buy some tokens
        uint256 buyAmount = 1000e18;
        (int256 costInt, ) = tokenEmitter.buyTokenQuote(buyAmount);
        uint256 cost = uint256(costInt);
        uint256 fee = tokenEmitter.computeTotalReward(cost);
        uint256 totalPayment = cost + fee;

        // record founder + user token balances
        uint256 founderBefore = erc20.balanceOf(founderRewardAddress);
        uint256 userBefore = erc20.balanceOf(user);

        ITokenEmitter.ProtocolRewardAddresses memory rewardAddrs = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        tokenEmitter.buyToken(user, buyAmount, totalPayment, rewardAddrs);

        vm.stopPrank();

        // founder reward check
        uint256 founderAfter = erc20.balanceOf(founderRewardAddress);
        uint256 userAfter = erc20.balanceOf(user);

        // By default 7% if >= 14
        uint256 expectedFounder = (buyAmount * 7) / 100;
        assertEq(founderAfter - founderBefore, expectedFounder, "Founder didn't get correct reward");
        assertEq(userAfter - userBefore, buyAmount, "User didn't get correct minted tokens");
    }

    // The following helper function is not strictly needed, but helps for code reuse:
    function _buySomeTokens(address buyer, uint256 buyAmount) internal {
        vm.startPrank(buyer);
        paymentToken.approve(address(tokenEmitter), type(uint256).max);

        // do a quote
        (int256 costInt, ) = tokenEmitter.buyTokenQuote(buyAmount);
        uint256 costForTokens = uint256(costInt);
        uint256 fee = tokenEmitter.computeTotalReward(costForTokens);
        uint256 totalPayment = costForTokens + fee;

        // set maxCost to a big number
        uint256 maxCost = totalPayment + 1e18;

        ITokenEmitter.ProtocolRewardAddresses memory rewardAddrs = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });
        tokenEmitter.buyToken(buyer, buyAmount, maxCost, rewardAddrs);

        vm.stopPrank();
    }
}
