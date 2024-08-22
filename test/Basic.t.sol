// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {FlowTest} from "./Flow.t.sol";
import {IFlowEvents,IFlow} from "../src/interfaces/IFlow.sol";
import {Flow} from "../src/Flow.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BasicFlowTest is FlowTest {

    function setUp() override public {
        super.setUp();
    }

    function testInitializeBasicParameters() public view {
        // Ensure the Flow contract is initialized correctly
        assertEq(address(Flow(flow).erc721Votes()), address(0x1));
        assertEq(Flow(flow).minVotingPowerToCreate(), 100 * 1e18);
        assertEq(Flow(flow).quorumVotesBPS(), 5000);
        assertEq(Flow(flow).tokenVoteWeight(), 1e18);

        // Check the snapshot block
        assertEq(Flow(flow).snapshotBlock(), block.number);

        // Check if the total member units is set to 1 if it was initially 0
        assertEq(Flow(flow).getTotalUnits(), 1);
    }

    function testInitializeContractState() public view {
        // Check if the superToken is set correctly
        assertEq(address(Flow(flow).superToken()), address(superToken));

        // Check if the pool is created and set correctly
        assertNotEq(address(Flow(flow).pool()), address(0));

        // Check if the flowImpl is set correctly
        assertEq(Flow(flow).flowImpl(), address(flowImpl));

        // Check if the contract is properly initialized as Ownable
        assertEq(Flow(flow).owner(), manager);
    }

    function testInitializePoolConfig() public {
        // Check if poolConfig is set correctly
        (bool transferabilityForUnitsOwner, bool distributionFromAnyAddress) = Flow(flow).getPoolConfig();
        assertEq(transferabilityForUnitsOwner, false);
        assertEq(distributionFromAnyAddress, false);

        // Check for event emission
        vm.expectEmit(true, true, true, true);
        emit IFlowEvents.FlowInitialized(manager, address(superToken), flowImpl);
        
        // Re-deploy the contract to emit the event
        address votingPowerAddress = address(0x1);
        deployFlow(votingPowerAddress, address(superToken));
    }

    function testInitializeFailures() public {
        // Test initialization with zero address for _nounsToken
        address flowProxy = address(new ERC1967Proxy(flowImpl, ""));
        vm.prank(address(manager));
        vm.expectRevert(IFlow.ADDRESS_ZERO.selector);
        IFlow(flowProxy).initialize({
            nounsToken: address(0),
            superToken: address(superToken),
            flowImpl: flowImpl,
            flowParams: flowParams
        });

        // Test initialization with zero address for _flowImpl
        address originalFlowImpl = flowImpl;
        flowProxy = address(new ERC1967Proxy(flowImpl, ""));
        vm.prank(address(manager));
        vm.expectRevert(IFlow.ADDRESS_ZERO.selector);
        IFlow(flowProxy).initialize({
            nounsToken: address(0x1),
            superToken: address(superToken),
            flowImpl: address(0),
            flowParams: flowParams
        });
        flowImpl = originalFlowImpl;

        // Test double initialization (should revert)
        vm.expectRevert("Initializable: contract is already initialized");
        Flow(payable(flow)).initialize(address(0x1), address(superToken), address(flowImpl), flowParams);
    }
}