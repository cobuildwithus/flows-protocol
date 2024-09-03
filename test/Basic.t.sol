// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {FlowTest} from "./Flow.t.sol";
import {IFlowEvents,IFlow} from "../src/interfaces/IFlow.sol";
import {Flow} from "../src/Flow.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FlowStorageV1} from "../src/storage/FlowStorageV1.sol";

contract BasicFlowTest is FlowTest {

    function setUp() override public {
        super.setUp();
    }

    function testInitializeBasicParameters() public view {
        // Ensure the Flow contract is initialized correctly
        assertEq(address(flow.erc721Votes()), address(nounsToken));
        assertEq(flow.tokenVoteWeight(), 1e18 * 1000);

        // Check if the total member units is set to 1 if it was initially 0
        assertEq(flow.getTotalUnits(), 1);
    }

    function testInitializeContractState() public view {
        // Check if the superToken is set correctly
        assertEq(address(flow.superToken()), address(superToken));

        // Check if the pool is created and set correctly
        assertNotEq(address(flow.pool()), address(0));

        // Check if the flowImpl is set correctly
        assertEq(flow.flowImpl(), address(flowImpl));

        // Check if the contract is properly initialized as Ownable
        assertEq(flow.owner(), manager);
    }

    function testInitializePoolConfig() public {
        // Check if poolConfig is set correctly
        (bool transferabilityForUnitsOwner, bool distributionFromAnyAddress) = flow.getPoolConfig();
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
            manager: manager, // Add this line
            parent: address(0),
            flowParams: flowParams,
            metadata: FlowStorageV1.RecipientMetadata("Test Flow", "ipfs://test", "Test Description")
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
            manager: manager, // Add this line
            parent: address(0),
            flowParams: flowParams,
            metadata: FlowStorageV1.RecipientMetadata("Test Flow", "ipfs://test", "Test Description")
        });
        flowImpl = originalFlowImpl;

        // Test double initialization (should revert)
        Flow(payable(flowProxy)).initialize(
            address(0x1),
            address(superToken),
            address(flowImpl),
            manager, // Add this line
            address(0),
            flowParams,
            FlowStorageV1.RecipientMetadata("Test Flow", "ipfs://test", "Test Description")
        );

        // Test double initialization (should revert)
        vm.expectRevert("Initializable: contract is already initialized");
        Flow(payable(flowProxy)).initialize(
            address(0x1),
            address(superToken),
            address(flowImpl),
            manager, // Add this line
            address(0),
            flowParams,
            FlowStorageV1.RecipientMetadata("Test Flow", "ipfs://test", "Test Description")
        );
    }

    function testAddFlowRecipient() public {
        FlowStorageV1.RecipientMetadata memory metadata = FlowStorageV1.RecipientMetadata({
            title: "Test Flow Recipient",
            description: "A test flow recipient",
            image: "ipfs://testimage"
        });
        address flowManager = address(0x123);

        vm.prank(manager);
        address newFlowRecipient = flow.addFlowRecipient(metadata, flowManager);

        assertNotEq(newFlowRecipient, address(0));

        address parent = address(flow);

        // Check if the new flow recipient is properly initialized
        Flow newFlow = Flow(newFlowRecipient);
        assertEq(address(newFlow.erc721Votes()), address(nounsToken));
        assertEq(address(newFlow.superToken()), address(superToken));
        assertEq(newFlow.flowImpl(), flowImpl);
        assertEq(newFlow.manager(), flowManager);
        assertEq(newFlow.parent(), parent);
        assertEq(newFlow.tokenVoteWeight(), flow.tokenVoteWeight());

        // Check if the recipient is added to the main flow contract
        (address recipient, bool removed, FlowStorageV1.RecipientType recipientType, FlowStorageV1.RecipientMetadata memory storedMetadata) = flow.recipients(flow.recipientCount() - 1);
        assertEq(uint(recipientType), uint(FlowStorageV1.RecipientType.FlowContract));
        assertEq(removed, false);
        assertEq(recipient, newFlowRecipient);
        assertEq(storedMetadata.title, metadata.title);
        assertEq(storedMetadata.description, metadata.description);
        assertEq(storedMetadata.image, metadata.image);

        // Test adding with zero address flowManager (should revert)
        vm.expectRevert(IFlow.ADDRESS_ZERO.selector);
        vm.prank(manager);
        flow.addFlowRecipient(metadata, address(0));

        // Test adding with non-manager address (should revert)
        vm.prank(address(0xdead));
        vm.expectRevert(IFlow.SENDER_NOT_MANAGER.selector);
        flow.addFlowRecipient(metadata, flowManager);
    }
}