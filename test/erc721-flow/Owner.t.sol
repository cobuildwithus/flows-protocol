// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { ERC721FlowTest } from "./ERC721Flow.t.sol";
import { IFlow } from "../../src/interfaces/IFlow.sol";
import { Flow } from "../../src/Flow.sol";
import { ERC721Flow } from "../../src/ERC721Flow.sol";
import { FlowTypes } from "../../src/storage/FlowStorageV1.sol";

contract OwnerFlowTest is ERC721FlowTest {
    function setUp() public override {
        super.setUp();
    }

    function testRemoveNonexistentRecipient() public {
        bytes32 nonexistentRecipientId = bytes32(""); // Assuming this ID doesn't exist

        vm.prank(manager); // Owner address
        vm.expectRevert(IFlow.INVALID_RECIPIENT_ID.selector);
        flow.removeRecipient(nonexistentRecipientId);
    }

    function testSetFlowImpl() public {
        address newFlowImpl = address(0x123);
        vm.prank(address(0)); // Non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        Flow(flow).setFlowImpl(newFlowImpl);

        vm.prank(manager); // Owner address
        Flow(flow).setFlowImpl(newFlowImpl);
        assertEq(Flow(flow).flowImpl(), newFlowImpl);
    }

    function testSetFlowRate() public {
        int96 newFlowRate = 10;
        vm.prank(address(1)); // Non-owner address
        vm.expectRevert(IFlow.NOT_OWNER_OR_PARENT.selector);
        Flow(flow).setFlowRate(newFlowRate);

        vm.prank(manager); // Owner address
        Flow(flow).setFlowRate(newFlowRate);
        assertEq(Flow(flow).getTotalFlowRate(), newFlowRate);
    }

    function testUpgrade() public {
        address newImplementation = address(new ERC721Flow());
        vm.prank(address(0)); // Non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        Flow(flow).upgradeTo(newImplementation);

        vm.prank(manager); // Owner address
        Flow(flow).upgradeTo(newImplementation);
        // Additional checks to verify upgrade might be needed
    }

    function testTransferOwnership() public {
        address newOwner = address(0x456);
        vm.prank(address(0)); // Non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        Flow(flow).transferOwnership(newOwner);

        vm.prank(manager); // Owner address
        Flow(flow).transferOwnership(newOwner);
        assertEq(Flow(flow).owner(), manager); // Ownership not transferred yet due to two-step process

        vm.prank(newOwner);
        Flow(flow).acceptOwnership();
        assertEq(Flow(flow).owner(), newOwner);
    }

    function testRenounceOwnership() public {
        vm.prank(address(0)); // Non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        Flow(flow).renounceOwnership();

        vm.prank(manager); // Owner address
        Flow(flow).renounceOwnership();
        assertEq(Flow(flow).owner(), address(0));
    }

    function testUpdateFlowRateAndManagerRewardPercentage() public {
        uint32 initialManagerRewardPercent = flow.managerRewardPoolFlowRatePercent();
        vm.prank(manager);
        ERC721Flow(flow).setManagerRewardFlowRatePercent(initialManagerRewardPercent);

        // Update flow rate and manager reward percentage
        int96 newFlowRate = ERC721Flow(flow).getTotalFlowRate();
        uint32 newManagerRewardPercent = 200000; // 20%
        vm.prank(manager);
        ERC721Flow(flow).setManagerRewardFlowRatePercent(newManagerRewardPercent);

        // Check updated values
        assertEq(ERC721Flow(flow).getTotalFlowRate(), newFlowRate);
        assertEq(ERC721Flow(flow).managerRewardPoolFlowRatePercent(), newManagerRewardPercent);

        // Mint token to owner and vote
        address tokenOwner = address(0x123);
        uint256 tokenId = 1;
        nounsToken.mint(tokenOwner, tokenId);

        // Add recipient
        address recipient = address(0x456);
        vm.prank(manager);
        (bytes32 recipientId, ) = flow.addRecipient(recipient, recipientMetadata);

        bytes32[] memory recipientIds = new bytes32[](1);
        recipientIds[0] = recipientId;
        uint32[] memory bps = new uint32[](1);
        bps[0] = flow.PERCENTAGE_SCALE(); // 100%

        vm.prank(tokenOwner);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        ERC721Flow(flow).castVotes(tokenIds, recipientIds, bps);

        // Check updated flow rates
        int96 expectedManagerRewardFlowRate = int96(
            uint96((uint256(uint96(newFlowRate)) * newManagerRewardPercent) / flow.PERCENTAGE_SCALE())
        );
        assertEq(
            ERC721Flow(flow).getManagerRewardPoolFlowRate(),
            expectedManagerRewardFlowRate,
            "Manager reward flow rate is not expected"
        );

        // remove recipient
        vm.prank(manager);
        flow.removeRecipient(recipientId);
        vm.pauseGasMetering();

        // Loop to add and remove random recipients 100 times
        for (uint256 i = 0; i < 1000; i++) {
            // Add a random recipient
            address randomRecipient = address(
                uint160(uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, block.number, i))))
            );

            // Add the recipient
            vm.prank(manager);
            (bytes32 randomRecipientId, ) = flow.addRecipient(randomRecipient, recipientMetadata);

            // Cast a vote for the new recipient
            bytes32[] memory newRecipientIds = new bytes32[](1);
            newRecipientIds[0] = randomRecipientId;
            uint32[] memory newBps = new uint32[](1);
            newBps[0] = flow.PERCENTAGE_SCALE(); // 100%

            vm.prank(tokenOwner);
            ERC721Flow(flow).castVotes(tokenIds, newRecipientIds, newBps);

            // Remove the recipient
            vm.prank(manager);
            flow.removeRecipient(randomRecipientId);

            // Verify that the recipient was removed
            FlowTypes.FlowRecipient memory removedRecipient = flow.getRecipientById(randomRecipientId);
            assertTrue(removedRecipient.removed, "Recipient should be removed");
        }

        // check that manager reward flow rate is expected
        assertApproxEqAbs(
            ERC721Flow(flow).getManagerRewardPoolFlowRate(),
            expectedManagerRewardFlowRate,
            1e9, // Allow for a small difference due to potential rounding
            "Manager reward flow rate is not approximately equal after removing recipient"
        );
    }

    function testMaxFlowRateAndManagerRewardPercentage() public {
        // Set max manager reward percentage
        uint32 maxManagerRewardPercent = flow.PERCENTAGE_SCALE(); // 100%
        vm.prank(manager);
        ERC721Flow(flow).setManagerRewardFlowRatePercent(maxManagerRewardPercent);

        // Check updated values
        assertEq(ERC721Flow(flow).managerRewardPoolFlowRatePercent(), maxManagerRewardPercent);
        assertEq(ERC721Flow(flow).getManagerRewardPoolFlowRate(), ERC721Flow(flow).getTotalFlowRate());

        // ensure bonus and baseline pool take up entire flow rate
        int96 baselinePoolFlowRate = ERC721Flow(flow).baselinePool().getTotalFlowRate();
        int96 bonusPoolFlowRate = ERC721Flow(flow).bonusPool().getTotalFlowRate();
        assertEq(baselinePoolFlowRate + bonusPoolFlowRate, 0);

        // Mint token to owner and vote
        address tokenOwner = address(0x456);
        uint256 tokenId = 2;
        nounsToken.mint(tokenOwner, tokenId);

        // Add recipient
        address recipient = address(0x789);
        vm.prank(manager);
        (bytes32 recipientId, ) = flow.addRecipient(recipient, recipientMetadata);

        bytes32[] memory recipientIds = new bytes32[](1);
        recipientIds[0] = recipientId;
        uint32[] memory bps = new uint32[](1);
        bps[0] = flow.PERCENTAGE_SCALE(); // 100%

        vm.prank(tokenOwner);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        ERC721Flow(flow).castVotes(tokenIds, recipientIds, bps);

        // Check that manager reward flow rate is equal to total flow rate
        assertEq(ERC721Flow(flow).getManagerRewardPoolFlowRate(), ERC721Flow(flow).getTotalFlowRate());
    }

    function testZeroFlowRateAndManagerRewardPercentage() public {
        // Set zero flow rate
        int96 zeroFlowRate = 0;
        vm.prank(manager);
        ERC721Flow(flow).setFlowRate(zeroFlowRate);

        // Set zero manager reward percentage
        uint32 zeroManagerRewardPercent = 0; // 0%
        vm.prank(manager);
        ERC721Flow(flow).setManagerRewardFlowRatePercent(zeroManagerRewardPercent);

        // Check updated values
        assertEq(ERC721Flow(flow).getTotalFlowRate(), zeroFlowRate);
        assertEq(ERC721Flow(flow).managerRewardPoolFlowRatePercent(), zeroManagerRewardPercent);
        // ensure bonus and baseline pool take up entire flow rate
        int96 totalFlowRate = ERC721Flow(flow).getTotalFlowRate();
        int96 baselinePoolFlowRate = ERC721Flow(flow).baselinePool().getTotalFlowRate();
        int96 bonusPoolFlowRate = ERC721Flow(flow).bonusPool().getTotalFlowRate();
        assertEq(baselinePoolFlowRate + bonusPoolFlowRate, totalFlowRate);

        // Mint token to owner and vote
        address tokenOwner = address(0x789);
        uint256 tokenId = 3;
        nounsToken.mint(tokenOwner, tokenId);

        address recipient = address(0x123);
        vm.prank(manager);
        (bytes32 recipientId, ) = flow.addRecipient(recipient, recipientMetadata);

        bytes32[] memory recipientIds = new bytes32[](1);
        recipientIds[0] = recipientId;

        uint32[] memory bps = new uint32[](1);
        bps[0] = flow.PERCENTAGE_SCALE(); // 100%

        vm.prank(tokenOwner);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        ERC721Flow(flow).castVotes(tokenIds, recipientIds, bps);

        // Check that manager reward flow rate is zero
        assertEq(ERC721Flow(flow).getManagerRewardPoolFlowRate(), 0);
    }

    function testZeroManagerRewardAndRemoveRecipient() public {
        // Set initial flow rate
        int96 initialFlowRate = 1000000; // A non-zero flow rate
        vm.prank(manager);
        ERC721Flow(flow).setFlowRate(initialFlowRate);

        // Add recipient
        address recipient = address(0x123);
        vm.prank(manager);
        (bytes32 recipientId, ) = flow.addRecipient(recipient, recipientMetadata);

        // Mint token to owner and vote
        address tokenOwner = address(0x789);
        uint256 tokenId = 3;
        nounsToken.mint(tokenOwner, tokenId);

        bytes32[] memory recipientIds = new bytes32[](1);
        recipientIds[0] = recipientId;

        uint32[] memory bps = new uint32[](1);
        bps[0] = flow.PERCENTAGE_SCALE(); // 100%

        vm.prank(tokenOwner);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        ERC721Flow(flow).castVotes(tokenIds, recipientIds, bps);

        // Set manager reward percentage to zero
        uint32 zeroManagerRewardPercent = 0; // 0%
        vm.prank(manager);
        ERC721Flow(flow).setManagerRewardFlowRatePercent(zeroManagerRewardPercent);

        // Check that manager reward flow rate is zero
        assertEq(ERC721Flow(flow).getManagerRewardPoolFlowRate(), 0);

        // Remove recipient
        vm.prank(manager);
        flow.removeRecipient(recipientId);

        // ensure that the manager reward pool flow rate is still zero
        assertEq(ERC721Flow(flow).getManagerRewardPoolFlowRate(), 0);

        // Verify recipient was removed
        FlowTypes.FlowRecipient memory removedRecipient = flow.getRecipientById(recipientId);
        assertEq(removedRecipient.removed, true);
    }
}
