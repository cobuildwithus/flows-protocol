// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { ERC721FlowTest } from "./ERC721Flow.t.sol";
import { IFlowEvents, IFlow, ICustomFlow, ICustomFlow } from "../../src/interfaces/IFlow.sol";
import { IAllocationStrategy } from "../../src/interfaces/IAllocationStrategy.sol";
import { CustomFlow } from "../../src/flows/CustomFlow.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";
import { ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import { IChainalysisSanctionsList } from "../../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";

contract BasicCustomFlowTest is ERC721FlowTest {
    function setUp() public override {
        super.setUp();
    }

    function testInitializeBasicParameters() public view {
        // Ensure the Flow contract is initialized correctly
        // Check if the total member units is set to 1 if it was initially 0
        assertEq(ISuperfluidPool(flow.baselinePool()).getTotalUnits(), 1);
        assertEq(ISuperfluidPool(flow.bonusPool()).getTotalUnits(), 1);
    }

    function testInitializeContractState() public view {
        // Check if the superToken is set correctly
        assertEq(address(flow.superToken()), address(superToken));

        // Check if the pool is created and set correctly
        assertNotEq(address(flow.bonusPool()), address(0));

        // Check if the flowImpl is set correctly
        assertEq(flow.flowImpl(), address(flowImpl));

        // Check if the reward pool is set correctly
        assertEq(flow.managerRewardPool(), address(dummyRewardPool));

        // Check if the contract is properly initialized as Ownable
        assertEq(flow.owner(), manager);
    }

    function testInitializeEventEmission() public {
        // Check for event emission
        vm.expectEmit(true, true, false, false);
        emit IFlowEvents.FlowInitialized(
            manager,
            address(superToken),
            flowImpl,
            manager,
            address(dummyRewardPool),
            address(0),
            address(0),
            address(0),
            0,
            0,
            strategies
        );

        // Re-deploy the contract to emit the event
        address flowProxy = address(new ERC1967Proxy(flowImpl, ""));

        vm.prank(address(manager));
        ICustomFlow(flowProxy).initialize({
            initialOwner: address(manager),
            superToken: address(superToken),
            flowImpl: flowImpl,
            manager: manager,
            managerRewardPool: address(dummyRewardPool),
            parent: address(0),
            flowParams: flowParams,
            metadata: flowMetadata,
            sanctionsOracle: IChainalysisSanctionsList(address(0)),
            strategies: strategies
        });
    }

    function testInitializeFailures() public {
        // Test initialization with zero address for _nounsToken
        address flowProxy = address(new ERC1967Proxy(flowImpl, ""));
        vm.prank(address(manager));
        vm.expectRevert(IFlow.ADDRESS_ZERO.selector);
        ICustomFlow(flowProxy).initialize({
            initialOwner: address(manager),
            superToken: address(superToken),
            flowImpl: flowImpl,
            manager: manager,
            managerRewardPool: address(dummyRewardPool),
            parent: address(0),
            flowParams: flowParams,
            metadata: FlowTypes.RecipientMetadata(
                "Test Flow",
                "ipfs://test",
                "Test Description",
                "Test Tagline",
                "https://example.com"
            ),
            sanctionsOracle: IChainalysisSanctionsList(address(0)),
            strategies: new IAllocationStrategy[](1)
        });

        // Test initialization with zero address for _flowImpl
        address originalFlowImpl = flowImpl;
        flowProxy = address(new ERC1967Proxy(flowImpl, ""));
        vm.prank(address(manager));
        vm.expectRevert(IFlow.ADDRESS_ZERO.selector);
        ICustomFlow(flowProxy).initialize({
            initialOwner: address(manager),
            strategies: strategies,
            superToken: address(superToken),
            flowImpl: address(0),
            manager: manager,
            managerRewardPool: address(dummyRewardPool),
            parent: address(0),
            flowParams: flowParams,
            metadata: FlowTypes.RecipientMetadata(
                "Test Flow",
                "ipfs://test",
                "Test Description",
                "Test Tagline",
                "https://example.com"
            ),
            sanctionsOracle: IChainalysisSanctionsList(address(0))
        });
        flowImpl = originalFlowImpl;

        // Test double initialization (should revert)
        ICustomFlow(payable(flowProxy)).initialize(
            address(manager),
            address(superToken),
            address(flowImpl),
            manager,
            address(dummyRewardPool),
            address(0),
            flowParams,
            FlowTypes.RecipientMetadata(
                "Test Flow",
                "ipfs://test",
                "Test Description",
                "Test Tagline",
                "https://example.com"
            ),
            IChainalysisSanctionsList(address(0)),
            strategies
        );

        // Test double initialization (should revert)
        vm.expectRevert("Initializable: contract is already initialized");
        ICustomFlow(payable(flowProxy)).initialize(
            address(manager),
            address(superToken),
            address(flowImpl),
            manager,
            address(dummyRewardPool),
            address(0),
            flowParams,
            FlowTypes.RecipientMetadata(
                "Test Flow",
                "ipfs://test",
                "Test Description",
                "Test Tagline",
                "https://example.com"
            ),
            IChainalysisSanctionsList(address(0)),
            strategies
        );
    }

    function testAddFlowRecipient() public {
        FlowTypes.RecipientMetadata memory metadata = FlowTypes.RecipientMetadata({
            title: "Test Flow Recipient",
            description: "A test flow recipient",
            image: "ipfs://testimage",
            tagline: "Test Flow Tagline",
            url: "https://testflow.com"
        });
        address flowManager = address(0x123);

        vm.prank(manager);
        bytes32 recipientId = keccak256(abi.encodePacked(flowManager));
        (, address newFlowRecipient) = flow.addFlowRecipient(
            recipientId,
            metadata,
            flowManager,
            address(0),
            strategies
        );

        assertNotEq(newFlowRecipient, address(0));

        address parent = address(flow);

        // Check if the new flow recipient is properly initialized
        CustomFlow newFlow = CustomFlow(newFlowRecipient);
        assertEq(address(newFlow.superToken()), address(superToken));
        assertEq(newFlow.flowImpl(), flowImpl);
        assertEq(newFlow.manager(), flowManager);
        assertEq(newFlow.parent(), parent);
        _checkStrategies(strategies, newFlow.strategies());

        // Check if the recipient is added to the main flow contract
        FlowTypes.FlowRecipient memory recipient = flow.getRecipientById(recipientId);
        assertEq(uint(recipient.recipientType), uint(FlowTypes.RecipientType.FlowContract));
        assertEq(recipient.removed, false);
        assertEq(recipient.recipient, newFlowRecipient);
        assertEq(recipient.metadata.title, metadata.title);
        assertEq(recipient.metadata.description, metadata.description);
        assertEq(recipient.metadata.image, metadata.image);
        assertEq(recipient.metadata.tagline, metadata.tagline);
        assertEq(recipient.metadata.url, metadata.url);

        // Test adding with zero address flowManager (should revert)
        vm.expectRevert(IFlow.ADDRESS_ZERO.selector);
        vm.prank(manager);
        flow.addFlowRecipient(
            keccak256(abi.encodePacked(address(0))),
            metadata,
            address(0),
            address(dummyRewardPool),
            strategies
        );

        // Test adding with non-manager address (should revert)
        vm.prank(address(0xdead));
        vm.expectRevert(IFlow.SENDER_NOT_MANAGER.selector);
        flow.addFlowRecipient(keccak256(abi.encodePacked(flowManager)), metadata, flowManager, address(0), strategies);
    }

    function _checkStrategies(
        IAllocationStrategy[] memory strategies,
        IAllocationStrategy[] memory newStrategies
    ) internal {
        assertEq(strategies.length, newStrategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            assertEq(address(strategies[i]), address(newStrategies[i]));
        }
    }

    function testSetFlowRateAccessControl() public {
        int96 newFlowRate = 1000;

        // Test that owner can call setFlowRate
        vm.prank(flow.owner());
        flow.setFlowRate(newFlowRate);
        assertEq(flow.getTotalFlowRate(), newFlowRate, "Owner should be able to set flow rate");

        // Test that parent can call setFlowRate
        vm.prank(flow.parent());
        flow.setFlowRate(newFlowRate * 2);
        assertEq(flow.getTotalFlowRate(), newFlowRate * 2, "Parent should be able to set flow rate");

        // Test that random address cannot call setFlowRate
        vm.prank(address(0xdead));
        vm.expectRevert(abi.encodeWithSelector(IFlow.NOT_OWNER_OR_PARENT.selector));
        flow.setFlowRate(newFlowRate * 4);
    }

    function testActiveRecipientCount() public {
        // Initial count should be 0
        assertEq(flow.activeRecipientCount(), 0, "Initial active recipient count should be 0");

        // Add a recipient
        FlowTypes.RecipientMetadata memory metadata = FlowTypes.RecipientMetadata({
            title: "Test Recipient",
            description: "A test recipient",
            image: "ipfs://test",
            tagline: "Test Recipient Tagline",
            url: "https://testrecipient.com"
        });
        vm.prank(manager);
        bytes32 recipientId = keccak256(abi.encodePacked(address(0x123)));
        flow.addRecipient(recipientId, address(0x123), metadata);
        assertEq(flow.activeRecipientCount(), 1, "Active recipient count should be 1 after adding");

        // Add another recipient
        vm.prank(manager);
        bytes32 recipientId2 = keccak256(abi.encodePacked(address(0x456)));
        flow.addRecipient(recipientId2, address(0x456), metadata);
        assertEq(flow.activeRecipientCount(), 2, "Active recipient count should be 2 after adding second recipient");

        // Remove a recipient
        vm.prank(manager);
        flow.removeRecipient(recipientId);
        assertEq(flow.activeRecipientCount(), 1, "Active recipient count should be 1 after removing");

        // Try to remove the same recipient again (should not affect the count)
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IFlow.RECIPIENT_ALREADY_REMOVED.selector));
        flow.removeRecipient(recipientId);
        assertEq(
            flow.activeRecipientCount(),
            1,
            "Active recipient count should still be 1 after trying to remove again"
        );

        // Remove the last recipient
        vm.prank(manager);
        flow.removeRecipient(recipientId2);
        assertEq(flow.activeRecipientCount(), 0, "Active recipient count should be 0 after removing all recipients");

        // Add a flow recipient
        address flowManager = address(0x789);
        vm.prank(manager);
        bytes32 flowRecipientId = keccak256(abi.encodePacked(flowManager));
        flow.addFlowRecipient(flowRecipientId, metadata, flowManager, address(0), strategies);
        assertEq(flow.activeRecipientCount(), 1, "Active recipient count should be 1 after adding flow recipient");

        // Verify total recipient count
        assertEq(flow.activeRecipientCount(), 1, "Total recipient count should be 1");
    }

    function testSetBaselineFlowRatePercent() public {
        // Initial setup
        int96 initialFlowRate = 1000000000; // 1 token per second
        vm.prank(manager);
        flow.setFlowRate(initialFlowRate);

        uint32 initialBaselinePercent = flow.baselinePoolFlowRatePercent();

        // Test setting a valid percentage
        uint32 newPercent = 500000; // 50%
        vm.prank(flow.owner());
        vm.expectEmit(true, true, false, true);
        emit IFlowEvents.BaselineFlowRatePercentUpdated(initialBaselinePercent, newPercent);
        flow.setBaselineFlowRatePercent(newPercent);

        assertEq(flow.baselinePoolFlowRatePercent(), newPercent, "Baseline percentage should be updated");

        // Verify flow rates are updated
        int96 totalFlowRate = flow.getTotalFlowRate();
        int96 baselineFlowRate = flow.baselinePool().getMemberFlowRate(address(flow));
        int96 bonusFlowRate = flow.bonusPool().getMemberFlowRate(address(flow));

        int256 flowScale = int256(uint256(flow.PERCENTAGE_SCALE()));

        int256 initialFlowRateMinusRewardPool = initialFlowRate -
            (initialFlowRate * int256(uint256(flow.managerRewardPoolFlowRatePercent()))) /
            flowScale;

        int256 expectedBaselineFlow = (int256(initialFlowRateMinusRewardPool) * int256(uint256(newPercent))) /
            flowScale;

        assertEq(totalFlowRate, initialFlowRate, "Total flow rate should remain unchanged");
        assertEq(baselineFlowRate, expectedBaselineFlow, "Baseline flow rate should be updated");
        assertEq(
            bonusFlowRate,
            initialFlowRateMinusRewardPool - baselineFlowRate,
            "Bonus flow rate should be the remainder"
        );

        // set manager to 0 first
        vm.prank(flow.owner());
        flow.setManagerRewardFlowRatePercent(0);

        // Test setting percentage to 100%
        uint32 percent = flow.PERCENTAGE_SCALE();
        vm.prank(flow.owner());
        flow.setBaselineFlowRatePercent(percent);
        assertEq(flow.baselinePoolFlowRatePercent(), percent, "Baseline percentage should be 100%");

        // Test setting percentage to 0%
        vm.prank(flow.owner());
        flow.setBaselineFlowRatePercent(0);
        assertEq(flow.baselinePoolFlowRatePercent(), 0, "Baseline percentage should be 0%");

        // Test setting percentage above 100%
        uint32 invalidPercent = flow.PERCENTAGE_SCALE() + 1;
        vm.prank(flow.owner());
        vm.expectRevert(abi.encodeWithSelector(IFlow.INVALID_PERCENTAGE.selector));
        flow.setBaselineFlowRatePercent(invalidPercent);

        // Test calling from non-owner/non-parent address
        vm.prank(address(0xdead));
        vm.expectRevert(abi.encodeWithSelector(IFlow.NOT_OWNER_OR_MANAGER.selector));
        flow.setBaselineFlowRatePercent(500000);

        // Test calling from parent address
        address parentAddress = flow.parent();
        vm.prank(parentAddress);
        vm.expectRevert(abi.encodeWithSelector(IFlow.NOT_OWNER_OR_MANAGER.selector));
        flow.setBaselineFlowRatePercent(300000); // 30%

        // Test calling from manager address
        address managerAddress = flow.manager();
        vm.prank(managerAddress);
        flow.setBaselineFlowRatePercent(250000); // 25%
        assertEq(flow.baselinePoolFlowRatePercent(), 250000, "Baseline percentage should be updated by parent");
    }

    function testSetManager() public {
        address initialManager = flow.manager();
        address newManager = address(0xbee);

        // Test calling from non-owner address
        vm.prank(address(0xdead));
        vm.expectRevert(abi.encodeWithSelector(IFlow.NOT_OWNER_OR_MANAGER.selector));
        flow.setManager(newManager);

        // Test calling from owner address
        vm.prank(flow.owner());
        vm.expectEmit(true, true, false, true);
        emit IFlowEvents.ManagerUpdated(initialManager, newManager);
        flow.setManager(newManager);

        assertEq(flow.manager(), newManager, "Manager should be updated");

        // Test setting manager to zero address
        vm.prank(flow.owner());
        vm.expectRevert(abi.encodeWithSelector(IFlow.ADDRESS_ZERO.selector));
        flow.setManager(address(0));

        // Verify that the manager was not changed
        assertEq(flow.manager(), newManager, "Manager should not be changed to zero address");
    }

    function testtotalAllocationWeight() public {
        // Mint some tokens to simulate total supply
        nounsToken.mint(address(0x1), 1);
        nounsToken.mint(address(0x2), 2);
        nounsToken.mint(address(0x3), 3);

        uint256 expectedTotalSupply = nounsToken.totalSupply();
        uint256 expectedTotalVoteWeight = expectedTotalSupply * 1e18 * 1000;

        _checkStrategies(strategies, flow.strategies());

        assertEq(
            flow.totalAllocationWeight(),
            expectedTotalVoteWeight,
            "Total token supply vote weight should match expected calculation"
        );
    }
}
