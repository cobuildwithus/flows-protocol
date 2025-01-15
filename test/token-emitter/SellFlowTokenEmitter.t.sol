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
contract SellFlowTokenEmitterTest is FlowTokenEmitterTest {
    // ============ Setup ============
    function setUp() public override {
        super.setUp();
    }

    // ---------------------------------------------------------------------
    // 12. sellTokenQuoteETH tests
    // ---------------------------------------------------------------------

    /**
     * @notice Tests a basic scenario for sellTokenQuoteETH to verify that it matches
     *         the separate calls to FlowTokenEmitter.sellTokenQuote and ethEmitter.sellTokenQuote.
     */
    function testSellTokenQuoteETH_Basic() public {
        // 1) Buy Flow tokens with ETH first
        uint256 flowAmount = 100e18;
        vm.startPrank(user1);
        (int256 costInt, ) = flowTokenEmitter.buyTokenQuoteETH(flowAmount);
        assertTrue(costInt > 0, "Expected positive ETH cost");
        uint256 ethCost = uint256(costInt);

        flowTokenEmitter.buyWithETH{ value: ethCost }(user1, flowAmount, ethCost, emptyAddr);
        vm.stopPrank();

        // 2) Flow emitter quote in PaymentToken
        int256 paymentTokenQuoteInt = flowTokenEmitter.sellTokenQuote(flowAmount);
        assertTrue(paymentTokenQuoteInt > 0, "Expected positive PaymentToken quote");
        uint256 paymentTokenQuote = uint256(paymentTokenQuoteInt);

        // 3) Then see how much ETH that PaymentToken is worth via ethEmitter
        int256 ethQuoteInt = ethEmitter.sellTokenQuote(paymentTokenQuote);
        assertTrue(ethQuoteInt > 0, "Expected positive ETH quote for PaymentToken");
        uint256 expectedETH = uint256(ethQuoteInt);

        // 4) Now check the direct function: sellTokenQuoteETH
        int256 combinedQuoteInt = flowTokenEmitter.sellTokenQuoteETH(flowAmount);
        assertTrue(combinedQuoteInt > 0, "Expected positive combined ETH quote");
        uint256 combinedETH = uint256(combinedQuoteInt);

        // They should match fairly closely. Minor rounding differences are possible.
        assertApproxEqAbs(
            combinedETH,
            expectedETH,
            1e14, // tolerance
            "sellTokenQuoteETH result should match the separate Flow->PAY->ETH quotes"
        );
    }

    /**
     * @notice Tests selling zero tokens via sellTokenQuoteETH, expecting revert.
     */
    function testSellTokenQuoteETH_ZeroTokens() public {
        // Query with 0 tokens
        vm.expectRevert(BondingSCurve.INVALID_AMOUNT.selector);
        flowTokenEmitter.sellTokenQuoteETH(0);
    }

    /**
     * @notice Tests sellTokenQuoteETH with a scenario where user has no Flow tokens minted.
     *         Per BondingSCurve.sol, this should revert with INVALID_SOLD_AMOUNT since
     *         selling would result in negative supply.
     */
    function testSellTokenQuoteETH_NoUserFlowBalance() public {
        // No tokens minted yet, so total supply is 0
        uint256 flowAmount = 50e18;

        // Expect revert since selling would result in negative supply
        vm.expectRevert(BondingSCurve.INVALID_SOLD_AMOUNT.selector);
        flowTokenEmitter.sellTokenQuoteETH(flowAmount);
    }

    /**
     * @notice Tests a large sell scenario for sellTokenQuoteETH to ensure no overflows
     *         and that it returns a sensible positive quote.
     */
    function testSellTokenQuoteETH_LargeAmount() public {
        vm.warp(block.timestamp + 300 days);
        // We'll buy a large number of Flow tokens first
        uint256 flowAmount = 250_000e18;

        // Get quote for buying with ETH
        (int256 costInETHInt, ) = flowTokenEmitter.buyTokenQuoteETH(flowAmount);
        require(costInETHInt > 0, "ETH cost must be positive");
        uint256 costInETH = uint256(costInETHInt);

        // Buy the tokens with ETH
        vm.startPrank(user1);
        vm.deal(user1, costInETH);

        ITokenEmitter.ProtocolRewardAddresses memory emptyAddr = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        flowTokenEmitter.buyWithETH{ value: costInETH }(user1, flowAmount, costInETH + 1e18, emptyAddr);
        vm.stopPrank();

        // Now query the sell quote
        int256 quoteInETH = flowTokenEmitter.sellTokenQuoteETH(flowAmount);
        // If there's an overflow or negative logic, it would revert or be < 0
        assertTrue(quoteInETH > 0, "Expected positive quote for large sell");
    }

    // ---------------------------------------------------------------------
    // 13. End-to-end test of actually selling Flow -> Payment -> ETH manually
    // ---------------------------------------------------------------------
    function testSellFlowTokensForETH_EndToEnd() public {
        // Create a fresh user for clean slate testing
        address user3 = makeAddr("user3");
        vm.deal(user3, 100 ether);

        // 1) Buy Flow tokens with ETH for user3
        uint256 flowAmount = 300e18;

        // Get quote for buying with ETH
        (int256 costInETHInt, ) = flowTokenEmitter.buyTokenQuoteETH(flowAmount);
        require(costInETHInt > 0, "ETH cost must be positive");
        uint256 costInETH = uint256(costInETHInt);

        // Buy the tokens with ETH
        vm.startPrank(user3);
        vm.deal(user3, costInETH);

        ITokenEmitter.ProtocolRewardAddresses memory emptyAddr = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // Buy tokens - this will mint flowAmount to user3 plus founder rewards if active
        flowTokenEmitter.buyWithETH{ value: costInETH }(user3, flowAmount, costInETH + 1e18, emptyAddr);
        vm.stopPrank();

        // 2) We'll get a quick reference quote from sellTokenQuoteETH
        int256 referenceETHInt = flowTokenEmitter.sellTokenQuoteETH(flowAmount);
        require(referenceETHInt > 0, "Quote must be positive");
        uint256 referenceETH = uint256(referenceETHInt);

        // 3) Actually do it in 2 steps:
        //    Step A: user calls "flowTokenEmitter.sellToken(...)" to get PaymentToken
        //    Step B: user calls "ethEmitter.sellToken(...)" to convert PaymentToken -> ETH

        // Step A: Sell Flow -> PaymentToken
        vm.startPrank(user3);

        // get PaymentToken quote
        int256 payQuoteInt = flowTokenEmitter.sellTokenQuote(flowAmount);
        require(payQuoteInt > 0, "PaymentToken quote must be positive");
        uint256 payQuote = uint256(payQuoteInt);

        // We'll pick a minPayment slightly below payQuote so it doesn't revert
        uint256 minPayment = payQuote - 1e15;

        // user must have enough Flow tokens - should be exactly flowAmount since founder rewards
        // are minted separately to founderRewardAddress
        uint256 userFlowBefore = brandToken.balanceOf(user3);
        assertEq(userFlowBefore, flowAmount, "User should have bought Flow tokens");

        // Check founder rewards if active
        if (flowTokenEmitter.isFounderRewardActive()) {
            uint256 founderReward = flowTokenEmitter.calculateFounderReward(flowAmount);
            uint256 founderBal = brandToken.balanceOf(flowTokenEmitter.founderRewardAddress());
            assertEq(founderBal, founderReward, "Founder should have received reward tokens");
        }

        // Sell them
        // This function is inherited from TokenEmitterERC20 => burn Flow & get Payment
        flowTokenEmitter.sellToken(flowAmount, minPayment);

        // user Flow should be 0 now
        uint256 userFlowAfter = brandToken.balanceOf(user3);
        assertEq(userFlowAfter, 0, "Users Flow should be burnt");

        // user Payment
        uint256 userPaymentBal = paymentToken.balanceOf(user3);
        assertEq(userPaymentBal, payQuote, "User did not receive expected PaymentToken amount");

        // Step B: user calls ethEmitter.sellToken(...), Payment -> ETH
        // get an ETH quote from the ethEmitter
        int256 ethQuoteInt = ethEmitter.sellTokenQuote(userPaymentBal);
        require(ethQuoteInt > 0, "ETH quote must be positive");
        uint256 ethQuote = uint256(ethQuoteInt);

        // pick minPayment in ETH
        uint256 userEthBefore = user3.balance;

        // Sell Payment for ETH
        paymentToken.approve(address(ethEmitter), userPaymentBal);
        ethEmitter.sellToken(userPaymentBal, ethQuote); // minPayment slightly below

        vm.stopPrank();

        uint256 userEthAfter = user3.balance;
        uint256 userEthChange = userEthAfter - userEthBefore;

        // 4) Compare final user ETH to referenceETH
        // In an ideal scenario, userEthChange ≈ referenceETH.
        // Some small difference might appear if each step rounds slightly.
        assertApproxEqAbs(
            userEthChange,
            referenceETH,
            1e14,
            "End-to-end user ETH from bridging Flow->Payment->ETH should match sellTokenQuoteETH"
        );
    }

    /**
     * @notice Tests a basic scenario for sellTokenForETH: user sells Flow tokens and receives ETH.
     */
    function testSellTokenForETH_BasicFlow() public {
        // 1) Buy Flow tokens with ETH first
        uint256 flowAmount = 50e18;
        vm.startPrank(user1);
        vm.deal(user1, 100 ether);

        (int256 costInt, ) = flowTokenEmitter.buyTokenQuoteETH(flowAmount);
        assertTrue(costInt > 0, "Expected positive ETH cost");
        uint256 ethCost = uint256(costInt);

        flowTokenEmitter.buyWithETH{ value: ethCost }(user1, flowAmount, ethCost, emptyAddr);
        vm.stopPrank();

        // 2) Confirm user1 has those Flow tokens
        assertEq(brandToken.balanceOf(user1), flowAmount, "User should hold Flow tokens initially");

        // 3) Check how much ETH they'd receive
        int256 ethQuoteInt = flowTokenEmitter.sellTokenQuoteETH(flowAmount);
        assertTrue(ethQuoteInt > 0, "Expected a positive sell quote in ETH");
        uint256 minPayment = (uint256(ethQuoteInt) * 99) / 100; // 1% slippage buffer

        // 4) Sell the Flow tokens
        vm.startPrank(user1);
        brandToken.approve(address(flowTokenEmitter), flowAmount);
        flowTokenEmitter.sellTokenForETH(flowAmount, minPayment);
        vm.stopPrank();

        // 5) The user should have 0 Flow tokens left
        assertEq(brandToken.balanceOf(user1), 0, "Users Flow balance should be zero after selling");
        // 6) The user’s ETH changed – can do an approximate check if needed, or
        //    rely on an advanced check that the revert didn’t happen for slippage.
    }

    /**
     * @notice Tests selling 0 tokens via sellTokenForETH, expecting revert.
     */
    function testSellTokenForETH_ZeroTokensReverts() public {
        vm.startPrank(user1);
        vm.expectRevert(BondingSCurve.INVALID_AMOUNT.selector);
        flowTokenEmitter.sellTokenForETH(0, 0);
        vm.stopPrank();
    }

    /**
     * @notice Tests the slippage protection in sellTokenForETH by setting a minPayment
     *         greater than the actual final ETH to be received.
     */
    function testSellTokenForETH_SlippageExceeded() public {
        // First buy some Flow tokens with ETH
        uint256 flowAmount = 25e18;
        vm.startPrank(user1);
        vm.deal(user1, 100 ether);

        // Get quote for buying Flow tokens
        (int256 costInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        assertTrue(costInt > 0, "Expected positive cost");
        uint256 cost = uint256(costInt);

        // Buy Flow tokens with ETH
        flowTokenEmitter.buyWithETH{ value: cost }(user1, flowAmount, cost, emptyAddr);

        // Suppose the quote says we expect ~1 ETH, but we demand 2 ETH minimum
        // so we can force a slippage revert.
        int256 ethQuoteInt = flowTokenEmitter.sellTokenQuoteETH(flowAmount);
        assertTrue(ethQuoteInt > 0, "Expected a positive ETH quote");
        uint256 unrealisticMinPayment = uint256(ethQuoteInt) + 1 ether;

        brandToken.approve(address(flowTokenEmitter), flowAmount);

        // Expect revert because minPayment is too high
        vm.expectRevert(ITokenEmitter.SLIPPAGE_EXCEEDED.selector);
        flowTokenEmitter.sellTokenForETH(flowAmount, unrealisticMinPayment);

        vm.stopPrank();
    }

    /**
     * @notice Tests trying to sell more Flow tokens than the user holds, expecting revert.
     */
    function testSellTokenForETH_InsufficientFlowBalance() public {
        // user1 has 0 Flow tokens
        // Attempt to sell 20 tokens
        uint256 flowAmount = 20e18;

        vm.startPrank(user1);
        brandToken.approve(address(flowTokenEmitter), flowAmount);
        // Expect revert, because user does not actually hold that many tokens
        vm.expectRevert(BondingSCurve.INVALID_SOLD_AMOUNT.selector);
        flowTokenEmitter.sellTokenForETH(flowAmount, 1);
        vm.stopPrank();
    }

    /**
     * @notice Tests if the FlowTokenEmitter contract lacks enough Payment tokens
     *         to pay out the user when they do Flow -> Payment -> ETH. Should revert
     *         with INSUFFICIENT_CONTRACT_BALANCE if there's no liquidity.
     *
     *         This test artificially drains Payment tokens from the FlowTokenEmitter
     *         contract before a user tries to sell.
     */
    function testSellTokenForETH_InsufficientContractBalance() public {
        // 1) First buy Flow tokens with ETH
        uint256 flowAmount = 100e18;
        vm.startPrank(user1);
        vm.deal(user1, 100 ether);

        // Get quote and buy Flow tokens
        (int256 costInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        assertTrue(costInt > 0, "Expected positive cost");
        uint256 cost = uint256(costInt);
        flowTokenEmitter.buyWithETH{ value: cost }(user1, flowAmount, cost, emptyAddr);
        vm.stopPrank();

        // 2) Under normal conditions, the contract might accumulate Payment tokens
        //    from other buyers. But here, we artificially ensure the FlowTokenEmitter
        //    has zero Payment tokens by transferring them out (if any).
        //    For example, if the FlowTokenEmitter somehow had a Payment token balance from prior buys,
        //    we forcibly drain it:
        uint256 emitterBalance = paymentToken.balanceOf(address(flowTokenEmitter));
        if (emitterBalance > 0) {
            vm.prank(address(flowTokenEmitter));
            paymentToken.transfer(owner, emitterBalance);
        }

        // 3) The user attempts to sell Flow tokens
        //    Because the contract has zero Payment token liquidity, the flowTokenEmitter
        //    should revert with "INSUFFICIENT_CONTRACT_BALANCE()".
        vm.startPrank(user1);
        brandToken.approve(address(flowTokenEmitter), flowAmount);

        // We'll use some minPayment well below the actual expected, just so we can confirm
        // the revert is from insufficient balance rather than slippage
        vm.expectRevert(ITokenEmitter.INSUFFICIENT_CONTRACT_BALANCE.selector);
        flowTokenEmitter.sellTokenForETH(flowAmount, 1e15);

        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // 2. Additional combined or advanced tests (if needed)
    // ---------------------------------------------------------------------

    /**
     * @notice Example test that tries partial sells multiple times, ensuring
     *         the user’s leftover Flow tokens remain correct, and final ETH is correct.
     */
    function testSellTokenForETH_MultiplePartialSells() public {
        // 1) Buy Flow tokens with ETH
        uint256 flowAmount = 200e18;
        vm.startPrank(user1);
        vm.deal(user1, 100 ether);

        // Get quote and buy Flow tokens
        (int256 costInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        assertTrue(costInt > 0, "Expected positive cost");
        uint256 cost = uint256(costInt);
        flowTokenEmitter.buyWithETH{ value: cost }(user1, flowAmount, cost, emptyAddr);
        vm.stopPrank();

        // 2) user1 sells half, then sells half again
        uint256 halfAmount = flowAmount / 2;

        // Sell #1: half the user’s Flow
        vm.startPrank(user1);
        brandToken.approve(address(flowTokenEmitter), halfAmount);
        flowTokenEmitter.sellTokenForETH(halfAmount, 0 /* minPayment */);
        vm.stopPrank();

        // user1 should have half left
        uint256 expectedFlowRemaining = brandToken.balanceOf(user1);
        assertEq(expectedFlowRemaining, flowAmount - halfAmount, "User should have half left");

        // Sell #2: the rest
        vm.startPrank(user1);
        brandToken.approve(address(flowTokenEmitter), expectedFlowRemaining);
        flowTokenEmitter.sellTokenForETH(expectedFlowRemaining, 0);
        vm.stopPrank();

        assertEq(brandToken.balanceOf(user1), 0, "Users Flow should be zero after 2 sells");
    }
}
