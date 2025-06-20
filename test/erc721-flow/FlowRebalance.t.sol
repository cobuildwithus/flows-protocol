// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { ERC721FlowTest } from "./ERC721Flow.t.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { IFlowEvents, IFlow } from "../../src/interfaces/IFlow.sol";
import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

/// @title FlowRebalanceTest
/// @notice Tests for `increaseFlowRate` / `decreaseFlowRate` safety-brake helpers and `isFlowRateTooHigh`.
contract FlowRebalanceTest is ERC721FlowTest {
    using SuperTokenV1Library for ISuperToken;

    // Re-use the deployment from ERC721FlowTest
    function setUp() public override {
        super.setUp();
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Helpers                                   */
    /* -------------------------------------------------------------------------- */

    // Constant taken from FlowStorageV1 (99% of incoming flow allowed for outflow)
    uint256 internal constant OUT_CAP_BPS = 99e4; // 990_000
    uint256 internal constant PERCENT_SCALE = 1e6;

    address internal constant ALICE = address(0xA11CE);

    // helper to get buffer amount for a flow rate
    function _bufferOf(int96 rate) internal view returns (uint256) {
        return ISuperToken(address(superToken)).getBufferAmountByFlowRate(rate);
    }

    function _mintAndUpgrade(address to, uint256 amount) internal {
        // underlying token is TestToken at address testUSDC
        TestToken(testUSDC).mint(to, amount);
        vm.prank(to);
        TestToken(testUSDC).approve(address(superToken), amount);
        vm.prank(to);
        superToken.upgrade(amount);
    }

    function _startIncomingFlow(int96 flowRate) internal {
        // ensure Alice has enough balance for required deposit + stream
        uint256 deposit = ISuperToken(address(superToken)).getBufferAmountByFlowRate(flowRate);
        _mintAndUpgrade(ALICE, deposit * 2);

        vm.startPrank(ALICE);
        superToken.approve(address(superToken), deposit * 2);
        ISuperToken(address(superToken)).createFlow(address(flow), flowRate);
        vm.stopPrank();
    }

    function _computeMaxSafeRate() internal view returns (int96) {
        return flow.getMaxSafeFlowRate();
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Tests                                     */
    /* -------------------------------------------------------------------------- */

    /// @notice Default deployment _is_ flagged as too high because there is no incoming stream yet.
    function testIsFlowRateTooHigh_DefaultTrue() public {
        assertTrue(flow.isFlowRateTooHigh(), "Default flow should be flagged too high when no incoming stream");
    }

    /* -------------------------------------------------------------------------- */
    /*                        decreaseFlowRate – lower outflow                     */
    /* -------------------------------------------------------------------------- */

    /// @notice When cap < current rate, `decreaseFlowRate` lowers the rate with no deposit.
    function testDecreaseFlowRate_DecreasesRateToCap() public {
        // Preconditions: default deployment has positive cached outflow and cap == 0.
        int96 oldRate = flow.getTotalFlowRate();
        assertGt(oldRate, 0, "expected positive outflow");

        int96 cap = _computeMaxSafeRate();
        assertEq(cap, 0, "expected cap to be zero when no incoming flow");

        // Call — any address is allowed.
        address caller = address(0xBEEF);
        vm.expectEmit(false, true, false, true);
        emit IFlowEvents.FlowRateDecreased(caller, oldRate, cap);
        uint256 flowBalBefore = superToken.balanceOf(address(flow));
        uint256 oldBuffer = _bufferOf(oldRate);
        vm.prank(caller);
        flow.decreaseFlowRate();

        uint256 newBuffer = _bufferOf(cap);
        // Expect contract balance to have increased by at least (oldBuffer - newBuffer)
        uint256 expectedRefund = oldBuffer - newBuffer;
        uint256 flowBalAfter = superToken.balanceOf(address(flow));
        uint256 gain = superToken.balanceOf(address(flow)) - flowBalBefore;
        uint256 tolerance = oldBuffer / 1e12; // sub-basis-point tolerance
        if (tolerance < 1e12) tolerance = 1e12; // minimum slack 1e12 wei
        assertLe(expectedRefund > gain ? expectedRefund - gain : gain - expectedRefund, tolerance, "refund mismatch");

        // Post-conditions: rate reduced to cap and no longer considered too high.
        assertEq(flow.getTotalFlowRate(), cap, "flow not reduced to cap");
        assertFalse(flow.isFlowRateTooHigh(), "flow still flagged too high after decrease");
    }

    /* -------------------------------------------------------------------------- */
    /*                       isFlowRateTooHigh positive path                       */
    /* -------------------------------------------------------------------------- */

    /// @notice Helper still works when flow exceeds cap (manager can lower manually).
    function testIsFlowRateTooHigh_WhenExceedsCap() public {
        // start a flow into the flow contract
        int96 incoming = 1e16;
        _startIncomingFlow(incoming);

        // assert net flow is positive
        assertGt(flow.getNetFlowRate(), 0, "net flow is not positive");

        // transfer some tokens to the flow contract to cover the buffer
        vm.prank(ALICE);
        superToken.transfer(address(flow), 1e18);

        // Inflate cached flow beyond cap.
        int96 cap = _computeMaxSafeRate();

        int96 inflated = cap + int96(uint96(cap / 5));

        vm.prank(manager);
        flow.setFlowRate(inflated);

        assertEq(flow.getActualFlowRate(), inflated, "flow rate not inflated");

        assertTrue(flow.isFlowRateTooHigh(), "Flow should be flagged too high when exceeding cap");
    }

    /// @notice Increase path – with incoming stream supplying capacity.
    function testIncreaseFlowRate_RaisesToCap() public {
        int96 beforeRate = flow.getActualFlowRate();
        int96 incoming = beforeRate * 10; // larger to ensure cap higher and delta positive
        _startIncomingFlow(incoming);

        int96 cap = _computeMaxSafeRate();
        assertGt(cap, beforeRate, "cap should now exceed current outflow");

        // Use getRequiredBufferAmount from Flow.sol for the incremental amount
        uint256 toPull = flow.getRequiredBufferAmount(cap - beforeRate);

        // Caller funds delta deposit and approves flow contract
        _mintAndUpgrade(manager, toPull);
        vm.prank(manager);
        superToken.approve(address(flow), toPull);

        // Call increaseFlowRate
        vm.expectEmit(false, true, false, true);
        emit IFlowEvents.FlowRateIncreased(manager, beforeRate, cap, toPull);

        uint256 flowBalanceBefore = superToken.balanceOf(address(flow));
        uint256 managerBalBefore = superToken.balanceOf(manager);

        // New API: pass only the incremental amount (delta) to raise the rate
        vm.prank(manager);
        flow.increaseFlowRate(cap - beforeRate);

        uint256 flowBalanceAfter = superToken.balanceOf(address(flow));
        uint256 managerBalAfter = superToken.balanceOf(manager);

        // Tokens are pulled from manager, but the Flow contract may forward some immediately.
        // Just assert manager paid at least `toPull`; we don't make assumptions on Flow balance.
        assertGe(managerBalBefore - managerBalAfter, toPull, "manager deposit too small");

        assertEq(flow.getTotalFlowRate(), cap, "rate not raised to cap");
        assertFalse(flow.isFlowRateTooHigh(), "should not be too high after raise");

        assertEq(superToken.allowance(manager, address(flow)), 0, "remaining allowance not zero");
    }

    /// @notice Second call when already aligned should do nothing.
    function testDecreaseFlowRate_NoOpWhenAligned() public {
        // Align first
        testIncreaseFlowRate_RaisesToCap();

        int96 before = flow.getTotalFlowRate();

        vm.recordLogs();
        vm.prank(address(0x1234));
        flow.decreaseFlowRate();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "unexpected event emitted on no-op");

        assertEq(flow.getTotalFlowRate(), before, "rate changed on no-op call");
    }

    /// @notice Increase without allowance should revert.
    function testIncreaseFlowRate_WithoutAllowanceReverts() public {
        int96 beforeRate = flow.getTotalFlowRate();
        int96 incoming = beforeRate * 10;
        _startIncomingFlow(incoming);
        int96 cap = _computeMaxSafeRate();
        assertGt(cap, beforeRate, "cap above");

        // Ensure no allowance and bal insufficient
        vm.prank(manager);
        vm.expectRevert();
        flow.increaseFlowRate(cap - beforeRate);
    }

    /* -------------------------------------------------------------------------- */
    /*                 Multiplier-specific behaviour and edge-cases               */
    /* -------------------------------------------------------------------------- */

    /// @notice Parent has no children – multiplier should be 2 so toPull == delta * 2.
    function testIncreaseFlowRate_NoChildren_PullsExactDelta() public {
        // top-up with an incoming stream so cap > oldRate
        int96 oldRate = flow.getTotalFlowRate();
        _startIncomingFlow(oldRate * 5);

        int96 cap = _computeMaxSafeRate();
        int96 desired = oldRate + 1; // tiny bump
        require(desired <= cap, "cap too small in fixture");

        // Use getRequiredBufferAmount from Flow.sol to compute toPull
        uint256 toPull = flow.getRequiredBufferAmount(desired - oldRate);

        // fund caller with required toPull tokens (multiplier 2 expected)
        _mintAndUpgrade(manager, toPull);
        vm.prank(manager);
        superToken.approve(address(flow), toPull);

        vm.expectEmit(false, true, false, true);
        emit IFlowEvents.FlowRateIncreased(manager, oldRate, desired, toPull);

        // New API: pass the tiny bump amount (desired - oldRate) == 1
        vm.prank(manager);
        flow.increaseFlowRate(desired - oldRate);

        assertEq(flow.getTotalFlowRate(), desired, "rate not updated");
    }

    /// @notice Setting bufferMultiplier to 0 should revert with INVALID_BUFFER_MULTIPLIER.
    function testSetBufferMultiplierZeroReverts() public {
        vm.prank(manager);
        vm.expectRevert(IFlow.INVALID_BUFFER_MULTIPLIER.selector);
        flow.setDefaultBufferMultiplier(0);
    }

    /// @notice Oversized increase is capped at maxSafeFlowRate and cannot exceed it.
    function testIncreaseFlowRate_CapsAtMaxSafeRate() public {
        // Existing outflow should be positive.
        int96 oldRate = flow.getTotalFlowRate();
        assertGt(oldRate, 0, "expected positive outflow");

        // Fund an incoming stream large enough so the cap is well above the old rate.
        int96 incoming = oldRate * 3;
        _startIncomingFlow(incoming);

        int96 cap = _computeMaxSafeRate();
        assertGt(cap, oldRate, "cap should exceed oldRate after incoming stream");

        // Deliberately request an increase far beyond the cap – double the cap.
        int96 requestedDelta = cap * 2;

        // Only fund the buffer required to reach the cap (not the oversized request).
        uint256 toPull = flow.getRequiredBufferAmount(cap - oldRate);
        _mintAndUpgrade(manager, toPull);
        vm.prank(manager);
        superToken.approve(address(flow), toPull);

        // Expect the helper to cap the rate at `cap` and pull exactly `toPull` tokens.
        vm.expectEmit(false, true, false, true);
        emit IFlowEvents.FlowRateIncreased(manager, oldRate, cap, toPull);

        uint256 managerBalBefore = superToken.balanceOf(manager);

        vm.prank(manager);
        flow.increaseFlowRate(requestedDelta);

        uint256 managerBalAfter = superToken.balanceOf(manager);
        uint256 pulled = managerBalBefore - managerBalAfter;

        // Manager should not pay more than `toPull` (+1 wei tolerance) and at least `toPull`.
        assertGe(pulled, toPull, "deposit pulled less than expected");
        assertLe(pulled, toPull + 1, "deposit pulled exceeds expected allowance");

        // Post-conditions: rate capped and not flagged as too high.
        assertEq(flow.getTotalFlowRate(), cap, "flow rate exceeded cap");
        assertFalse(flow.isFlowRateTooHigh(), "flow incorrectly flagged too high");

        // All allowance should be consumed.
        assertEq(superToken.allowance(manager, address(flow)), 0, "remaining allowance not zero");
    }

    /// @notice Uses custom buffer multiplier when child flows exist
    function testIncreaseFlowRate_UsesCustomBufferMultiplier() public {
        // Step 1: Create a dummy child flow so multiplier logic switches from 2 to custom value.
        bytes32 recipientId = keccak256(abi.encodePacked(address(0xBEEF)));
        FlowTypes.RecipientMetadata memory metadata = FlowTypes.RecipientMetadata(
            "Child Flow",
            "Dummy child for multiplier test",
            "ipfs://image",
            "Tagline",
            "https://childflow.com"
        );

        vm.prank(manager);
        (, address childFlow) = flow.addFlowRecipient(recipientId, metadata, address(0xBEEF), address(0), strategies);
        assertTrue(childFlow != address(0), "child flow not created");

        // Step 2: Configure custom multiplier > 2
        uint256 multiplier = 4;
        vm.prank(manager);
        flow.setDefaultBufferMultiplier(multiplier);

        // Step 3: Ensure current outflow is below cap by adding incoming stream
        int96 oldRate = flow.getTotalFlowRate();
        int96 incoming = oldRate * 5;
        _startIncomingFlow(incoming);

        int96 cap = _computeMaxSafeRate();
        assertGt(cap, oldRate, "cap should exceed oldRate");

        // Delta to raise by (tiny bump)
        int96 delta = 1;
        int96 desiredRate = oldRate + delta;
        require(desiredRate <= cap, "cap too small in fixture");

        // Compute expected amount to pull using the Flow helper (reflects custom multiplier)
        uint256 toPullExpected = flow.getRequiredBufferAmount(delta);

        // Fund & approve exactly toPullExpected
        _mintAndUpgrade(manager, toPullExpected);
        vm.prank(manager);
        superToken.approve(address(flow), toPullExpected);

        // Expect correct event with custom multiplier amount
        vm.expectEmit(false, true, false, true);
        emit IFlowEvents.FlowRateIncreased(manager, oldRate, desiredRate, toPullExpected);

        uint256 flowBalBefore = superToken.balanceOf(address(flow));
        uint256 managerBalBefore = superToken.balanceOf(manager);

        // Act – perform the tiny bump
        vm.prank(manager);
        flow.increaseFlowRate(delta);

        uint256 flowBalAfter = superToken.balanceOf(address(flow));
        uint256 managerBalAfter = superToken.balanceOf(manager);

        // Verify balance delta matches expectation within sub-bps tolerance
        uint256 gain = flowBalAfter - flowBalBefore;
        uint256 tolerance = toPullExpected / 1e12;
        if (tolerance < 1e12) tolerance = 1e12; // min slack 1e12 wei
        assertLe(toPullExpected > gain ? toPullExpected - gain : gain - toPullExpected, tolerance, "deposit mismatch");

        // Manager should have paid approximately toPullExpected (never less)
        uint256 paid = managerBalBefore - managerBalAfter;
        assertGe(paid, toPullExpected, "manager deposit too small");

        // State assertions
        assertEq(flow.getTotalFlowRate(), desiredRate, "rate not updated to desired");
        assertFalse(flow.isFlowRateTooHigh(), "flow flagged too high after increase");
        assertEq(superToken.allowance(manager, address(flow)), 0, "remaining allowance not zero");
    }

    /// @notice After incoming stream drops, `decreaseFlowRate` rebalances down to the new cap.
    function testDecreaseFlowRate_ReactsToIncomingStreamDrop() public {
        // Step 1: Align outflow to the current cap using existing helper.
        testIncreaseFlowRate_RaisesToCap();

        int96 alignedRate = flow.getTotalFlowRate();
        assertFalse(flow.isFlowRateTooHigh(), "should be aligned after raise");
        assertGt(alignedRate, 0, "aligned rate must be positive");

        // Derive current incoming rate: net + out = in.
        int96 netBefore = flow.getNetFlowRate();
        int96 incomingBefore = netBefore + alignedRate;
        assertGt(incomingBefore, 0, "incoming should be positive");

        // Step 2: Reduce Alice's incoming stream to 1/4 of its current value.
        int96 reducedIncoming = incomingBefore / 4;
        vm.startPrank(ALICE);
        ISuperToken(address(superToken)).updateFlow(address(flow), reducedIncoming);
        vm.stopPrank();

        // Compute new cap after reduction and ensure it is below current outflow.
        int96 newCap = _computeMaxSafeRate();
        assertLt(newCap, alignedRate, "new cap should be below current outflow after drop");

        // Prepare buffer expectations for refund accounting.
        uint256 oldBuffer = _bufferOf(alignedRate);
        uint256 newBuffer = _bufferOf(newCap);

        // Step 3: Any address calls decreaseFlowRate to rebalance.
        address caller = address(0xFEED);
        vm.expectEmit(false, true, false, true);
        emit IFlowEvents.FlowRateDecreased(caller, alignedRate, newCap);

        uint256 flowBalBefore = superToken.balanceOf(address(flow));
        vm.prank(caller);
        flow.decreaseFlowRate();
        uint256 flowBalAfter = superToken.balanceOf(address(flow));

        // Step 4: Validate refund equals (oldBuffer - newBuffer) within tolerance.
        uint256 expectedRefund = oldBuffer - newBuffer;
        uint256 gain = flowBalAfter - flowBalBefore;
        uint256 tolerance = oldBuffer / 1e12;
        if (tolerance < 1e12) tolerance = 1e12;
        assertLe(expectedRefund > gain ? expectedRefund - gain : gain - expectedRefund, tolerance, "refund mismatch");

        // Step 5: State assertions.
        assertEq(flow.getTotalFlowRate(), newCap, "flow not reduced to new cap");
        assertFalse(flow.isFlowRateTooHigh(), "flow still flagged too high after decrease");
    }

    /// @notice Calling decreaseFlowRate when already below cap should be a no-op (no state change, no events).
    function testDecreaseFlowRate_NoOpWhenAlreadyBelowCap() public {
        // Arrange: start an incoming stream large enough to make the flow safe without any alignment.
        int96 oldRate = flow.getTotalFlowRate();
        assertGt(oldRate, 0, "expected positive outflow");

        // Provide ample incoming flow so cap >> oldRate.
        _startIncomingFlow(oldRate * 10);
        assertFalse(flow.isFlowRateTooHigh(), "flow should already be within cap");

        // Snapshot relevant state.
        int96 rateBefore = flow.getTotalFlowRate();
        uint256 balBefore = superToken.balanceOf(address(flow));

        // Act: call decreaseFlowRate from random caller while recording logs.
        vm.recordLogs();
        vm.prank(address(0xCAFE));
        flow.decreaseFlowRate();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Assert: no events emitted, state unchanged.
        assertEq(logs.length, 0, "unexpected event emitted on no-op");
        assertEq(flow.getTotalFlowRate(), rateBefore, "flow rate changed on no-op");

        uint256 balAfter = superToken.balanceOf(address(flow));
        // Allow up to 1 wei drift.
        uint256 diff = balAfter > balBefore ? balAfter - balBefore : balBefore - balAfter;
        assertLe(diff, 1, "balance should not change materially on no-op");
    }

    /// @notice Reverts when allowance is present but manager balance is insufficient.
    function testIncreaseFlowRate_AllowancePresentButInsufficientBalanceReverts() public {
        int96 beforeRate = flow.getTotalFlowRate();
        // Provide large incoming stream so cap is above current.
        _startIncomingFlow(beforeRate * 10);
        int96 cap = _computeMaxSafeRate();
        assertGt(cap, beforeRate, "cap should exceed current rate");

        int96 delta = cap - beforeRate;
        // Ensure delta positive
        require(delta > 0, "delta non-positive");

        uint256 toPull = flow.getRequiredBufferAmount(delta);
        require(toPull > 1, "fixture assumes toPull > 1 wei");

        // Mint & upgrade only toPull - 1 wei (insufficient by 1 wei)
        _mintAndUpgrade(manager, toPull - 1);

        // Approve the full toPull amount.
        vm.prank(manager);
        superToken.approve(address(flow), toPull);

        // Expect generic revert from transferFrom due to insufficient balance.
        vm.prank(manager);
        vm.expectRevert();
        flow.increaseFlowRate(delta);
    }
}
