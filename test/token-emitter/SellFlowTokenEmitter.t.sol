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
        // 1) Mint user some Flow tokens
        uint256 flowAmount = 100e18;
        vm.startPrank(address(flowTokenEmitter));
        brandToken.mint(user1, flowAmount);
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
        assertEq(userFlowAfter, 0, "User's Flow should be burnt");

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
}
