// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { ERC721FlowTest } from "./ERC721Flow.t.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { IFlowEvents, IFlow } from "../../src/interfaces/IFlow.sol";
import { Vm } from "forge-std/Vm.sol";

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
        // ensure Alice has enough balance for required deposit
        uint256 deposit = ISuperToken(address(superToken)).getBufferAmountByFlowRate(flowRate);
        _mintAndUpgrade(ALICE, deposit * 2);

        vm.startPrank(ALICE);
        superToken.approve(address(superToken), deposit * 2);
        ISuperToken(address(superToken)).createFlow(address(flow), flowRate);
        vm.stopPrank();
    }

    /// @dev Re-implements the `_getMaxFlowRate` calculation locally for assertions.
    function _computeMaxSafeRate() internal view returns (int96) {
        int96 netFlow = int96(ISuperToken(address(superToken)).getNetFlowRate(address(flow)));
        int96 outFlow = flow.getTotalFlowRate();
        int96 inFlow = netFlow + outFlow; // incoming = net + outgoing

        if (inFlow <= 0) return 0;

        uint256 capped = (uint256(uint96(inFlow)) * OUT_CAP_BPS) / PERCENT_SCALE;
        return int96(uint96(capped));
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
        // Inflate cached flow beyond cap.
        int96 cap = _computeMaxSafeRate();
        int96 inflated = cap + int96(uint96(cap / 5 + 1));
        vm.prank(manager);
        flow.setFlowRate(inflated);

        assertTrue(flow.isFlowRateTooHigh(), "Flow should be flagged too high when exceeding cap");
    }

    /// @notice Increase path – with incoming stream supplying capacity.
    function testIncreaseFlowRate_RaisesToCap() public {
        int96 beforeRate = flow.getTotalFlowRate();
        int96 incoming = beforeRate * 10; // larger to ensure cap higher and delta positive
        _startIncomingFlow(incoming);

        int96 cap = _computeMaxSafeRate();
        assertGt(cap, beforeRate, "cap should now exceed current outflow");

        uint256 oldBuffer = _bufferOf(beforeRate);
        uint256 newBuffer = _bufferOf(cap);
        require(newBuffer > oldBuffer, "delta non-positive");
        uint256 delta = newBuffer - oldBuffer;
        uint256 toPull = delta * 2; // multiplier = 2 when no children present

        // Caller funds delta deposit and approves flow contract
        _mintAndUpgrade(manager, toPull);
        vm.prank(manager);
        superToken.approve(address(flow), toPull);

        // Call increaseFlowRate
        vm.expectEmit(false, true, false, true);
        emit IFlowEvents.FlowRateIncreased(manager, beforeRate, cap, toPull);

        uint256 flowBalanceBefore = superToken.balanceOf(address(flow));
        uint256 managerBalBefore = superToken.balanceOf(manager);

        vm.prank(manager);
        flow.increaseFlowRate(cap);

        uint256 flowBalanceAfter = superToken.balanceOf(address(flow));
        uint256 managerBalAfter = superToken.balanceOf(manager);

        // Tokens are pulled from manager, but the Flow contract may forward some immediately.
        // Just assert manager paid at least `delta`; we don't make assumptions on Flow balance.
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
        flow.increaseFlowRate(cap);
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

        uint256 oldBuf = _bufferOf(oldRate);
        uint256 newBuf = _bufferOf(desired);
        uint256 delta = newBuf - oldBuf;
        uint256 toPull = delta * 2;

        // fund caller with required toPull tokens (multiplier 2 expected)
        _mintAndUpgrade(manager, toPull);
        vm.prank(manager);
        superToken.approve(address(flow), toPull);

        vm.expectEmit(false, true, false, true);
        emit IFlowEvents.FlowRateIncreased(manager, oldRate, desired, toPull);

        vm.prank(manager);
        flow.increaseFlowRate(desired);

        assertEq(flow.getTotalFlowRate(), desired, "rate not updated");
    }

    /// @notice Setting bufferMultiplier to 0 should revert with INVALID_BUFFER_MULTIPLIER.
    function testSetBufferMultiplierZeroReverts() public {
        vm.prank(manager);
        vm.expectRevert(IFlow.INVALID_BUFFER_MULTIPLIER.selector);
        flow.setDefaultBufferMultiplier(0);
    }
}
