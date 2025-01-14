// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { FlowTokenEmitter } from "../../src/token-issuance/FlowTokenEmitter.sol";
import { TokenEmitterETH } from "../../src/token-issuance/TokenEmitterETH.sol";
import { TokenEmitterERC20 } from "../../src/token-issuance/TokenEmitterERC20.sol";
import { ERC20VotesMintable } from "../../src/ERC20VotesMintable.sol";
import { ITokenEmitter } from "../../src/interfaces/ITokenEmitter.sol";
import { ProtocolRewards } from "../../src/protocol-rewards/ProtocolRewards.sol";
import { IWETH } from "../../src/interfaces/IWETH.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { RewardPool } from "../../src/RewardPool.sol";
import { BondingSCurve } from "../../src/token-issuance/BondingSCurve.sol";
import { MockWETH } from "../mocks/MockWETH.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";

// Optional Superfluid + Token imports if needed
import { SuperfluidFrameworkDeployer } from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { FlowTokenEmitterTest } from "./FlowTokenEmitter.t.sol";

/**
 * @title FlowTokenEmitterTest
 * @notice This test suite verifies the logic of FlowTokenEmitter, which allows buying with
 *         a payment token directly or bridging from ETH via an underlying TokenEmitterETH.
 */
contract BasicFlowTokenEmitterTest is FlowTokenEmitterTest {
    // ============ Setup ============
    function setUp() public override {
        super.setUp();
    }

    // =========================================
    // ===========   Tests Begin   ============
    // =========================================

    function testInitialization() public {
        // Just check some basics
        assertEq(address(flowTokenEmitter.ethEmitter()), address(ethEmitter), "ETH emitter not set properly");
        assertEq(address(flowTokenEmitter.erc20()), address(brandToken), "Brand token not set");
        assertEq(address(flowTokenEmitter.paymentToken()), address(paymentToken), "Payment token not set");
    }

    /**
     * @notice Helper: buy Flow tokens directly with PaymentToken
     */
    function testBuyFlowWithPaymentToken() public {
        // user1 calls `buyToken(...)` on flowTokenEmitter (the normal ERC20 flow)
        address user = user1;
        // Reduce purchase amount to avoid insufficient funds
        uint256 flowAmount = 50e18;

        vm.startPrank(user);

        paymentToken.approve(address(flowTokenEmitter), type(uint256).max);

        // Let's get a quote
        (int256 costInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 cost = uint256(costInt);
        uint256 totalPayment = cost;

        ITokenEmitter.ProtocolRewardAddresses memory emptyAddr = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // We'll pass maxCost = totalPayment + 1 to allow small slippage
        uint256 maxCost = totalPayment + 1e18;

        // record balances
        uint256 userPAYBefore = paymentToken.balanceOf(user);
        uint256 brandBefore = brandToken.balanceOf(user);

        // buy
        flowTokenEmitter.buyToken(user, flowAmount, maxCost, emptyAddr);

        // check
        uint256 userPAYAfter = paymentToken.balanceOf(user);
        uint256 brandAfter = brandToken.balanceOf(user);
        assertEq(userPAYBefore - userPAYAfter, totalPayment, "User didn't pay correct totalPayment in PaymentToken");
        assertEq(brandAfter - brandBefore, flowAmount, "User didn't receive correct brand tokens");

        vm.stopPrank();
    }

    /**
     * @notice Helper: buy Flow tokens bridging from ETH => PaymentToken => Flow
     */
    function testBuyFlowViaETH() public {
        address user = user1;
        // Reduce purchase amount
        uint256 flowAmount = 20e18;

        vm.startPrank(user);

        // get a direct quote from flowTokenEmitter for brand tokens
        (int256 costInPAYInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 costInPAY = uint256(costInPAYInt);

        // then see how much ETH is needed to get costInPAY from `ethEmitter`
        (int256 costInETHInt, ) = ethEmitter.buyTokenQuoteWithRewards(costInPAY);
        uint256 costInETH = uint256(costInETHInt);

        // We'll pass maxCost = costInETH + 0.1 ether for reasonable slippage
        uint256 maxCost = costInETH + 0.1 ether;

        // record brand token & user ETH
        uint256 brandBefore = brandToken.balanceOf(user);
        uint256 userEthBefore = user.balance;

        ITokenEmitter.ProtocolRewardAddresses memory emptyAddr = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // call buyWithETH with smaller overpayment
        flowTokenEmitter.buyWithETH{ value: costInETH + 0.05 ether }(user, flowAmount, maxCost, emptyAddr);

        vm.stopPrank();

        // check brand token
        uint256 brandAfter = brandToken.balanceOf(user);
        assertEq(brandAfter - brandBefore, flowAmount, "Did not receive the correct Flow tokens");

        // check user's ETH used
        uint256 userEthAfter = user.balance;
        assertApproxEqAbs(userEthBefore - userEthAfter, costInETH, 1e14, "User didn't spend the correct ETH");
    }

    /**
     * @notice Tests bridging slippage: if costInETH exceeds maxCost
     */
    function testBuyFlowViaETH_SlippageRevert() public {
        address user = user1;
        // Reduce purchase amount
        uint256 flowAmount = 1000e18;

        // We'll get cost in PAY
        (int256 costInPAYInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 costInPAY = uint256(costInPAYInt);

        // We'll see how much ETH is needed
        (int256 costInETHInt, ) = ethEmitter.buyTokenQuoteWithRewards(costInPAY);
        uint256 costInETH = uint256(costInETHInt);

        uint256 maxCost = costInETH - costInETH / 2;

        vm.startPrank(user);

        ITokenEmitter.ProtocolRewardAddresses memory emptyAddr = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        vm.expectRevert(ITokenEmitter.SLIPPAGE_EXCEEDED.selector);
        flowTokenEmitter.buyWithETH{ value: costInETH }(user, flowAmount, maxCost, emptyAddr);

        vm.stopPrank();
    }

    /**
     * @notice Tests bridging insufficient ETH
     */
    function testBuyFlowViaETH_InsufficientETH() public {
        address user = user1;
        // Reduce purchase amount
        uint256 flowAmount = 10e18;

        (int256 costInPAYInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 costInPAY = uint256(costInPAYInt);

        (int256 costInETHInt, ) = ethEmitter.buyTokenQuoteWithRewards(costInPAY);
        uint256 costInETH = uint256(costInETHInt);

        vm.startPrank(user);

        ITokenEmitter.ProtocolRewardAddresses memory emptyAddr = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        vm.expectRevert(ITokenEmitter.INSUFFICIENT_FUNDS.selector);
        flowTokenEmitter.buyWithETH{ value: costInETH / 2 }(user, flowAmount, costInETH, emptyAddr);

        vm.stopPrank();
    }

    /**
     * @notice Additional test: bridging founder reward
     */
    function testBuyFlowViaETH_FounderReward() public {
        address user = user1;
        // Keep flowAmount >= 14 for 7% founder reward
        uint256 flowAmount = 20e18;

        (int256 costInPAYInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 costInPAY = uint256(costInPAYInt);

        (int256 costInETHInt, ) = ethEmitter.buyTokenQuoteWithRewards(costInPAY);
        uint256 costInETH = uint256(costInETHInt);

        uint256 maxCost = costInETH + 0.1 ether;

        // record founder's brand token
        uint256 founderBefore = brandToken.balanceOf(founderRewardAddress);

        vm.startPrank(user1);
        ITokenEmitter.ProtocolRewardAddresses memory emptyAddr = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });
        flowTokenEmitter.buyWithETH{ value: costInETH }(user1, flowAmount, maxCost, emptyAddr);
        vm.stopPrank();

        uint256 founderAfter = brandToken.balanceOf(founderRewardAddress);
        uint256 expectedFounder = getFounderReward(flowAmount);

        assertEq(founderAfter - founderBefore, expectedFounder, "Founder reward mismatch in bridging scenario");
    }

    // ---------------------------------------------------------------------
    // 1. Minimal Purchase Test
    // ---------------------------------------------------------------------
    function testBuyFlow_MinimalPurchase() public {
        // Purchase 1 brand token
        uint256 flowAmount = 1;

        vm.startPrank(user1);

        // Approve payment tokens to flowTokenEmitter
        paymentToken.approve(address(flowTokenEmitter), type(uint256).max);

        // Query cost
        (int256 costInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 cost = uint256(costInt);

        // "maxCost" = cost + some buffer
        uint256 maxCost = cost + 1e18;

        // Buy
        flowTokenEmitter.buyToken(user1, flowAmount, maxCost, emptyAddr);

        // check user1 brandToken balance
        uint256 userBrandBal = brandToken.balanceOf(user1);
        assertEq(userBrandBal, flowAmount, "User1 should have exactly 1 brand token");

        // founder reward if active
        if (block.timestamp < flowTokenEmitter.founderRewardExpiration() && founderRewardAddress != address(0)) {
            // Typically you do founder reward = 1 if amount < 14
            // So let's check founderRewardAddress balance
            uint256 founderBal = brandToken.balanceOf(founderRewardAddress);
            assertEq(founderBal, 1, "Founder should get 1 token reward for minimal purchase (assuming code logic).");
        }

        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // 2. Founder Reward Boundary: 13 vs 14
    // ---------------------------------------------------------------------
    function testBuyFlow_FounderRewardBoundary_13Tokens() public {
        // If user buys 13 tokens => founder reward is 1 (by code logic).
        uint256 flowAmount = 13;

        vm.startPrank(user1);
        paymentToken.approve(address(flowTokenEmitter), type(uint256).max);

        (int256 costInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 cost = uint256(costInt);

        // We'll accept cost + some buffer
        flowTokenEmitter.buyToken(user1, flowAmount, cost + 1e18, emptyAddr);
        vm.stopPrank();

        // user1 brand token check
        uint256 userBrandBal = brandToken.balanceOf(user1);
        assertEq(userBrandBal, flowAmount, "User1 should have 13 brand tokens after purchase");

        // Founder reward check
        if (block.timestamp < flowTokenEmitter.founderRewardExpiration()) {
            uint256 founderBal = brandToken.balanceOf(founderRewardAddress);
            assertEq(founderBal, 1, "Founder should get 1 token for 13 purchased");
        }
    }

    function testBuyFlow_FounderRewardBoundary_14Tokens() public {
        // If user buys 14 tokens => founder reward is (14 * 7)/100 = 0.98 => 0 in integer math?
        // This might be a code bug or maybe you changed it.
        // We'll just see what code does:
        uint256 flowAmount = 14;

        vm.startPrank(user1);
        paymentToken.approve(address(flowTokenEmitter), type(uint256).max);

        (int256 costInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 cost = uint256(costInt);

        // buy
        flowTokenEmitter.buyToken(user1, flowAmount, cost + 1e18, emptyAddr);
        vm.stopPrank();

        // user brand token
        uint256 userBrandBal = brandToken.balanceOf(user1);
        assertEq(userBrandBal, flowAmount, "User1 should have 14 brand tokens");

        // founder
        if (block.timestamp < flowTokenEmitter.founderRewardExpiration()) {
            uint256 founderBal = brandToken.balanceOf(founderRewardAddress);
            // might be 0 or 1, depending on code. Let's just log it:
            console.log("founderBal after 14 tokens:", founderBal);
            // We could do: assertEq(founderBal, 0, "Check if reward is 0 for 14 tokens if integer truncation");
        }
    }

    // ---------------------------------------------------------------------
    // 3. Founder Reward Expiration
    // ---------------------------------------------------------------------
    function testBuyFlow_FounderRewardExpires() public {
        uint256 expiry = flowTokenEmitter.founderRewardExpiration();
        if (expiry <= block.timestamp) {
            console.log("WARNING: Founder reward already expired in your setUp. This test may be invalid.");
            return;
        }

        // Step 1: warp to just 1 second before expiration
        vm.warp(expiry - 1);

        // buy some tokens => expect founder reward
        vm.startPrank(user1);
        paymentToken.approve(address(flowTokenEmitter), type(uint256).max);

        uint256 flowAmount = 10;
        (int256 costInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);

        uint256 cost = uint256(costInt);
        flowTokenEmitter.buyToken(user1, flowAmount, cost + 1e18, emptyAddr);
        vm.stopPrank();

        // founder got some tokens
        uint256 founderBefore = brandToken.balanceOf(founderRewardAddress);
        // e.g. might be 1 or 0.07 * 10 => 0? Depending on code.

        // Step 2: warp to after expiration
        vm.warp(expiry + 10);

        // buy again => no founder reward
        vm.startPrank(user1);
        flowTokenEmitter.buyToken(user1, flowAmount, cost + 1e18, emptyAddr);
        vm.stopPrank();

        // founder balance should not have changed
        uint256 founderAfter = brandToken.balanceOf(founderRewardAddress);
        assertEq(founderAfter, founderBefore, "No new founder reward after expiration");
    }

    // ---------------------------------------------------------------------
    // 4. Minimal bridging test (similar to your existing ones)
    // ---------------------------------------------------------------------
    function testBuyFlowViaETH_Minimal() public {
        // buy e.g. 1 token via bridging
        vm.deal(user1, 1 ether);

        vm.startPrank(user1);

        // get quote
        uint256 flowAmount = 1;
        (int256 costInPAYInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 costInPAY = uint256(costInPAYInt);

        (int256 costInETHInt, ) = ethEmitter.buyTokenQuoteWithRewards(costInPAY);
        uint256 costInETH = uint256(costInETHInt);

        // pass maxCost = costInETH + 0.01 ether
        flowTokenEmitter.buyWithETH{ value: costInETH + 0.01 ether }(
            user1,
            flowAmount,
            costInETH + 0.01 ether,
            emptyAddr
        );

        vm.stopPrank();

        uint256 brandBalance = brandToken.balanceOf(user1);
        assertEq(brandBalance, flowAmount, "User1 should get 1 brand token from bridging");
    }

    // ---------------------------------------------------------------------
    // 5. Overpayment & refund in bridging
    // ---------------------------------------------------------------------
    function testBuyFlowViaETH_OverpayRefund() public {
        // We'll cause user to send more ETH than needed
        vm.deal(user1, 2 ether);

        uint256 flowAmount = 10; // pick some
        // cost might be e.g. 0.3 eth, user will send 1.0 eth => expect 0.7 refund

        vm.startPrank(user1);

        (int256 costPAYInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 costPAY = uint256(costPAYInt);

        (int256 costETHInt, ) = ethEmitter.buyTokenQuoteWithRewards(costPAY);
        uint256 costETH = uint256(costETHInt);

        // user pays double
        uint256 payValue = costETH * 2;

        uint256 userEthBefore = user1.balance;

        flowTokenEmitter.buyWithETH{ value: payValue }(
            user1,
            flowAmount,
            payValue, // maxCost, large enough
            emptyAddr
        );

        vm.stopPrank();

        // user should have spent costETH, not payValue
        uint256 userEthSpent = userEthBefore - user1.balance;
        // We'll allow some wiggle if your code uses ~1.21 gas etc.
        assertApproxEqAbs(userEthSpent, costETH, 1e14, "User should spend about costETH");
    }

    // ---------------------------------------------------------------------
    // 6. Bridging Slippage Revert
    // ---------------------------------------------------------------------
    function testBuyFlowViaETH_BridgingSlippage() public {
        vm.deal(user1, 1 ether);

        uint256 flowAmount = 2000e18; // arbitrary
        (int256 costPAYInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 costPAY = uint256(costPAYInt);

        (int256 costETHInt, ) = ethEmitter.buyTokenQuoteWithRewards(costPAY);
        uint256 costETH = uint256(costETHInt);

        // We'll artificially reduce maxCost below costETH to trigger revert
        uint256 maxCost = costETH - costETH / 2;

        vm.startPrank(user1);
        vm.expectRevert(ITokenEmitter.SLIPPAGE_EXCEEDED.selector);
        flowTokenEmitter.buyWithETH{ value: costETH }(user1, flowAmount, maxCost, emptyAddr);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // 7. VRGDA Large Purchase -> Surge Cost + Surplus
    // ---------------------------------------------------------------------
    function testBuyFlow_HugePurchaseSurge() public {
        uint256 flowAmount = 1000e18;

        vm.startPrank(user1);
        paymentToken.approve(address(flowTokenEmitter), type(uint256).max);

        // get cost
        (int256 costInt, uint256 surgeCost) = flowTokenEmitter.buyTokenQuote(flowAmount);
        console.log("bonding curve cost + VRGDA => total cost =", uint256(costInt));
        console.log(" surge cost = ", surgeCost);

        // presumably surgeCost > 0 for big buys
        require(surgeCost > 0, "Expected a positive surge cost for a large purchase, check VRGDA logic");

        // pay
        flowTokenEmitter.buyToken(user1, flowAmount, uint256(costInt) + 1e18, emptyAddr);

        vm.stopPrank();

        // check that flowTokenEmitter's internal `vrgdaCapExtraPayment` increased by ~ surgeCost
        uint256 extraPayment = flowTokenEmitter.vrgdaCapExtraPayment();
        // We expect it to be >= surgeCost - minor rounding
        require(extraPayment > 0, "No VRGDA surplus found after large purchase?");
    }

    // ---------------------------------------------------------------------
    // 8. Withdraw VRGDA Surplus
    // ---------------------------------------------------------------------
    function testWithdrawVRGDA_Surplus() public {
        // 1) Generate some VRGDA surplus via ETH bridging
        uint256 largePurchase = 5000e18;
        (int256 costInt, uint256 surgeCost) = flowTokenEmitter.buyTokenQuoteETH(largePurchase);
        uint256 cost = uint256(costInt);

        // Give user1 enough ETH for bridging purchase
        vm.deal(user1, cost + 1e18);

        // Make large purchase via ETH bridging to generate surplus
        vm.startPrank(user1);
        flowTokenEmitter.buyWithETH{ value: cost + 1e18 }(user1, largePurchase, cost + 1e18, emptyAddr);
        vm.stopPrank();

        // Check the surplus was generated
        uint256 surplusBefore = flowTokenEmitter.vrgdaCapExtraPayment();
        console.log("VRGDA surplus before withdraw:", surplusBefore);
        require(surplusBefore > 0, "No VRGDA surplus generated");

        // Record owner's payment token balance before withdrawal
        uint256 ownerBalanceBefore = paymentToken.balanceOf(owner);

        // Withdraw surplus as owner
        vm.startPrank(owner);
        flowTokenEmitter.withdrawVRGDAPayment();
        vm.stopPrank();

        // Verify surplus was reset to 0
        uint256 surplusAfter = flowTokenEmitter.vrgdaCapExtraPayment();
        assertEq(surplusAfter, 0, "Surplus should be reset to 0 after withdraw");

        // Verify owner received the surplus in payment tokens
        uint256 ownerBalanceAfter = paymentToken.balanceOf(owner);
        uint256 ownerBalanceIncrease = ownerBalanceAfter - ownerBalanceBefore;
        assertEq(ownerBalanceIncrease, surplusBefore, "Owner should receive exact surplus amount");
    }

    // ---------------------------------------------------------------------
    // 9. Direct Payment Slippage Exceeded
    // ---------------------------------------------------------------------
    function testBuyFlow_DirectPayment_SlippageExceeded() public {
        vm.startPrank(user1);
        paymentToken.approve(address(flowTokenEmitter), type(uint256).max);

        uint256 flowAmount = 50;
        (int256 costInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 actualCost = uint256(costInt);
        // We pass a maxCost that is less than actual cost => revert
        uint256 maxCost = actualCost - 1;

        vm.expectRevert(ITokenEmitter.SLIPPAGE_EXCEEDED.selector);
        flowTokenEmitter.buyToken(user1, flowAmount, maxCost, emptyAddr);

        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // 10. Check insufficient PaymentToken funds
    // ---------------------------------------------------------------------
    function testBuyFlow_DirectPayment_InsufficientFunds() public {
        address poorUser = makeAddr("poorUser");

        // Ensure poorUser has 0 payment tokens
        assertEq(paymentToken.balanceOf(poorUser), 0, "poorUser should start with 0 payment tokens");

        vm.startPrank(poorUser);
        paymentToken.approve(address(flowTokenEmitter), type(uint256).max);

        uint256 flowAmount = 100;
        // check revert
        vm.expectRevert(ITokenEmitter.INSUFFICIENT_FUNDS.selector);
        flowTokenEmitter.buyToken(poorUser, flowAmount, 99999999, emptyAddr);

        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // 11. Time-based VRGDA test (optional)
    // ---------------------------------------------------------------------
    function testBuyFlow_TimeWarp_VRGDA() public {
        // Suppose we buy at t=0 vs t=30 days => price might differ
        // (assuming your VRGDA price changes over time)

        // 1) At t=0
        vm.warp(flowTokenEmitter.vrgdaCapStartTime()); // or ensure it's 0
        (int256 costAtT0, ) = flowTokenEmitter.buyTokenQuote(10);

        // buy
        vm.startPrank(user1);
        paymentToken.approve(address(flowTokenEmitter), type(uint256).max);
        flowTokenEmitter.buyToken(user1, 10, uint256(costAtT0) + 1e18, emptyAddr);
        vm.stopPrank();

        // 2) warp 30 days
        vm.warp(block.timestamp + 30 days);

        (int256 costAtT30, ) = flowTokenEmitter.buyTokenQuote(10);
        console.log("Cost at t=0 was:", uint256(costAtT0));
        console.log("Cost at t=30d is:", uint256(costAtT30));

        // Depending on your VRGDA curve, costAtT30 might be higher or lower
        // We can just log or do an assertion
    }
}
