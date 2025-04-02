// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { FlowTCRTest } from "./FlowTCR.t.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";
import { IArbitrator } from "../../src/tcr/interfaces/IArbitrator.sol";
import { IArbitrable } from "../../src/tcr/interfaces/IArbitrable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IGeneralizedTCR } from "../../src/tcr/interfaces/IGeneralizedTCR.sol";
import { IERC721Flow } from "../../src/interfaces/IFlow.sol";
import { RewardPool } from "../../src/RewardPool.sol";
import { IFlow } from "../../src/interfaces/IFlow.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TCRFundFlowTest is FlowTCRTest {
    // Helper function to get ERC20 balance of a contract or address
    function getERC20Balance(address _token, address _account) internal view returns (uint256) {
        return IERC20(_token).balanceOf(_account);
    }

    /**
     * @notice Test ERC20 transfer flow during item lifecycle where challenger wins
     * @dev This test covers the following steps:
     * 1. Submit an item
     * 2. Challenge the item
     * 3. Vote and execute the ruling in favor of the challenger
     * 4. Verify final balances
     */
    function testERC20TransfersDuringItemChallengerWinsLifecycle() public {
        uint256 arbitratorCost = arbitrator.arbitrationCost(bytes(""));

        // Record initial balances
        uint256[4] memory initialBalances = getRelevantBalances();

        // Submit an item
        bytes32 itemID = submitItem(EXTERNAL_ACCOUNT_ITEM_DATA, requester);

        // Verify balances after submission
        assertBalanceChange(requester, initialBalances[0], -int256(SUBMISSION_BASE_DEPOSIT + arbitratorCost));
        assertBalanceChange(address(flowTCR), initialBalances[2], int256(SUBMISSION_BASE_DEPOSIT + arbitratorCost));

        // Challenge the item
        challengeItem(itemID, challenger);

        // Verify balances after challenge
        assertBalanceChange(
            challenger,
            initialBalances[1],
            -int256(SUBMISSION_CHALLENGE_BASE_DEPOSIT + arbitratorCost)
        );
        assertBalanceChange(
            address(flowTCR),
            initialBalances[2],
            int256(SUBMISSION_BASE_DEPOSIT + SUBMISSION_CHALLENGE_BASE_DEPOSIT + arbitratorCost)
        );

        // Get dispute ID and execute voting in favor of the challenger
        (, uint256 disputeID, , , , , , , , ) = flowTCR.getRequestInfo(itemID, 0);
        voteAndExecute(disputeID, IArbitrable.Party.Challenger);

        // Verify final balances
        assertBalanceChange(requester, initialBalances[0], -int256(SUBMISSION_BASE_DEPOSIT + arbitratorCost));
        assertBalanceChange(challenger, initialBalances[1], int256(SUBMISSION_BASE_DEPOSIT));
        assertBalanceChange(address(flowTCR), initialBalances[2], 0);
        assertBalanceChange(address(arbitrator), initialBalances[3], int256(arbitratorCost));
    }

    /**
     * @notice Test ERC20 transfer flow during item lifecycle where requester wins
     * @dev This test covers the following steps:
     * 1. Submit an item
     * 2. Challenge the item
     * 3. Vote and execute the ruling in favor of the requester
     * 4. Verify final balances
     */
    function testERC20TransfersDuringItemRequesterWinsLifecycle() public {
        _testERC20TransfersDuringItemRequesterWinsLifecycle(EXTERNAL_ACCOUNT_ITEM_DATA);
        _testERC20TransfersDuringItemRequesterWinsLifecycle(FLOW_RECIPIENT_ITEM_DATA);
    }

    /**
     * @notice Helper function to test ERC20 transfer flow during item lifecycle where requester wins
     * @param itemData The data of the item to be submitted (can be external account or flow contract)
     */
    function _testERC20TransfersDuringItemRequesterWinsLifecycle(bytes memory itemData) internal {
        uint256 arbitratorCost = arbitrator.arbitrationCost(bytes(""));

        // Record initial balances
        uint256[4] memory initialBalances = getRelevantBalances();

        // Submit an item
        bytes32 itemID = submitItem(itemData, requester);

        // Verify balances after submission
        assertBalanceChange(requester, initialBalances[0], -int256(SUBMISSION_BASE_DEPOSIT + arbitratorCost));
        assertBalanceChange(address(flowTCR), initialBalances[2], int256(SUBMISSION_BASE_DEPOSIT + arbitratorCost));

        // Challenge the item
        challengeItem(itemID, challenger);

        // Verify balances after challenge
        assertBalanceChange(
            challenger,
            initialBalances[1],
            -int256(SUBMISSION_CHALLENGE_BASE_DEPOSIT + arbitratorCost)
        );
        assertBalanceChange(
            address(flowTCR),
            initialBalances[2],
            int256(SUBMISSION_BASE_DEPOSIT + SUBMISSION_CHALLENGE_BASE_DEPOSIT + arbitratorCost)
        );

        // Get dispute ID and execute voting
        (, uint256 disputeID, , , , , , , , ) = flowTCR.getRequestInfo(itemID, 0);
        voteAndExecute(disputeID, IArbitrable.Party.Requester);

        // Verify final balances
        assertBalanceChange(requester, initialBalances[0], int256(SUBMISSION_CHALLENGE_BASE_DEPOSIT));
        assertBalanceChange(
            challenger,
            initialBalances[1],
            -int256(SUBMISSION_CHALLENGE_BASE_DEPOSIT + arbitratorCost)
        );
        assertBalanceChange(address(flowTCR), initialBalances[2], 0);
        assertBalanceChange(address(arbitrator), initialBalances[3], int256(arbitratorCost));

        // Verify item registration
        (bytes memory data, IGeneralizedTCR.Status status, ) = flowTCR.getItemInfo(itemID);
        assertEq(data, itemData, "Item data should match");
        assertEq(uint256(status), uint256(IGeneralizedTCR.Status.Registered), "Item should be registered");

        // Verify Flow recipient creation
        (address recipientAddress, , FlowTypes.RecipientType recipientType) = abi.decode(
            itemData,
            (address, FlowTypes.RecipientMetadata, FlowTypes.RecipientType)
        );
        bytes32 recipientId = itemID;
        FlowTypes.FlowRecipient memory storedRecipient = flow.getRecipientById(recipientId);

        if (recipientType == FlowTypes.RecipientType.ExternalAccount) {
            assertEq(storedRecipient.recipient, recipientAddress, "Flow recipient address should match");
            assertGt(flow.getMemberTotalFlowRate(recipientAddress), 0, "Member units should be greater than 0");
        } else if (recipientType == FlowTypes.RecipientType.FlowContract) {
            assertTrue(
                storedRecipient.recipientType == FlowTypes.RecipientType.FlowContract,
                "Recipient type should be FlowContract"
            );
            assertNotEq(storedRecipient.recipient, address(0), "Flow contract address should not be zero");
        }
        assertTrue(flow.recipientExists(storedRecipient.recipient), "Flow recipient should exist");
    }

    /**
     * @notice Get balances of relevant addresses
     * @return balances Array of balances in the order: requester, challenger, generalizedTCR, arbitrator
     */
    function getRelevantBalances() internal view returns (uint256[4] memory balances) {
        balances[0] = erc20Token.balanceOf(requester);
        balances[1] = erc20Token.balanceOf(challenger);
        balances[2] = erc20Token.balanceOf(address(flowTCR));
        balances[3] = erc20Token.balanceOf(address(arbitrator));
    }

    /**
     * @notice Assert the change in balance of an address
     * @param account The address to check
     * @param initialBalance The initial balance of the account
     * @param expectedChange The expected change in balance (can be negative)
     */
    function assertBalanceChange(address account, uint256 initialBalance, int256 expectedChange) internal view {
        int256 actualChange = int256(erc20Token.balanceOf(account)) - int256(initialBalance);
        assertEq(
            actualChange,
            expectedChange,
            string(abi.encodePacked("Unexpected balance change for ", Strings.toHexString(uint160(account), 20)))
        );
    }

    function testSuccessfulItemAdditionWithoutChallenge(bytes memory itemData) internal {
        // 1. Setup initial balances
        uint256[4] memory initialBalances = getRelevantBalances();
        uint256 arbitratorCost = arbitrator.arbitrationCost(bytes(""));

        // 2. Approve GeneralizedTCR to spend tokens
        vm.prank(requester);
        erc20Token.approve(address(flowTCR), SUBMISSION_BASE_DEPOSIT + arbitratorCost);

        // 4. Call addItem function
        bytes32 itemID = submitItem(itemData, requester);

        // 5. Verify GeneralizedTCR balance increase
        assertEq(
            erc20Token.balanceOf(address(flowTCR)),
            initialBalances[2] + SUBMISSION_BASE_DEPOSIT + arbitratorCost,
            "GeneralizedTCR balance should increase by submission base deposit and arbitration cost"
        );

        // 6. Call executeRequest
        vm.warp(block.timestamp + flowTCR.challengePeriodDuration() + 1);
        flowTCR.executeRequest(itemID);

        // 7. Check requester's balance restoration
        assertEq(
            erc20Token.balanceOf(requester),
            initialBalances[0],
            "Requester balance should be restored after execution"
        );

        // 8. Ensure GeneralizedTCR balance decrease
        assertEq(
            erc20Token.balanceOf(address(flowTCR)),
            initialBalances[2],
            "GeneralizedTCR balance should return to initial state"
        );

        // 9. Verify no arbitrator costs deducted
        assertEq(
            erc20Token.balanceOf(address(arbitrator)),
            initialBalances[3],
            "Arbitrator balance should remain unchanged"
        );

        // 10. Assert final balances
        assertEq(
            erc20Token.balanceOf(requester),
            initialBalances[0],
            "Requester final balance should match initial balance"
        );
        assertEq(
            erc20Token.balanceOf(challenger),
            initialBalances[1],
            "Challenger final balance should remain unchanged"
        );
        assertEq(
            erc20Token.balanceOf(address(flowTCR)),
            initialBalances[2],
            "GeneralizedTCR final balance should match initial balance"
        );
        assertEq(
            erc20Token.balanceOf(address(arbitrator)),
            initialBalances[3],
            "Arbitrator final balance should remain unchanged"
        );
    }

    function testSuccessfulExternalAccountItemAdditionWithoutChallenge() public {
        testSuccessfulItemAdditionWithoutChallenge(EXTERNAL_ACCOUNT_ITEM_DATA);
    }

    function testSuccessfulFlowContractItemAdditionWithoutChallenge() public {
        testSuccessfulItemAdditionWithoutChallenge(FLOW_RECIPIENT_ITEM_DATA);
    }

    function testDisputeTieRefund(bytes memory itemData) internal {
        uint256[4] memory initialBalances = getRelevantBalances();
        uint256 arbitratorCost = arbitrator.arbitrationCost(bytes(""));

        // Initial setup
        bytes32 itemID = submitItem(itemData, requester);

        // Challenge the item
        challengeItem(itemID, challenger);

        // Get the dispute ID
        (, uint256 disputeID, , , , , , , , ) = flowTCR.getRequestInfo(itemID, 0);

        // Advance time to voting period
        advanceTime(VOTING_DELAY + 2);

        // Commit votes for a tie
        bytes32 requesterCommitHash = keccak256(abi.encode(uint256(1), "For registration", bytes32("salt")));
        vm.prank(requester);
        arbitrator.commitVote(disputeID, requesterCommitHash);

        bytes32 challengerCommitHash = keccak256(abi.encode(uint256(2), "Against registration", bytes32("salt2")));
        vm.prank(challenger);
        arbitrator.commitVote(disputeID, challengerCommitHash);

        // Advance time to reveal period
        advanceTime(VOTING_PERIOD);

        // Reveal votes
        vm.prank(requester);
        arbitrator.revealVote(disputeID, requester, 1, "For registration", bytes32("salt"));

        vm.prank(challenger);
        arbitrator.revealVote(disputeID, challenger, 2, "Against registration", bytes32("salt2"));

        // Advance time to end of reveal
        advanceTime(REVEAL_PERIOD);

        // Execute the ruling
        arbitrator.executeRuling(disputeID);

        // Check if both parties got their deposits back
        assertBalanceChange(requester, initialBalances[0], -int256(arbitratorCost / 2));
        assertBalanceChange(challenger, initialBalances[1], -int256(arbitratorCost / 2));

        assertBalanceChange(address(flowTCR), initialBalances[2], 0);

        // Verify arbitrator received payment
        assertBalanceChange(address(arbitrator), initialBalances[3], int256(arbitratorCost));

        // Verify the item status
        (, IGeneralizedTCR.Status status, ) = flowTCR.getItemInfo(itemID);
        assertEq(uint256(status), uint256(IGeneralizedTCR.Status.Absent), "Item should remain absent after a tie");
    }

    function testDisputeTieRefundExternalAccount() public {
        testDisputeTieRefund(EXTERNAL_ACCOUNT_ITEM_DATA);
    }

    function testDisputeTieRefundFlowContract() public {
        testDisputeTieRefund(FLOW_RECIPIENT_ITEM_DATA);
    }

    function testAddFlowRecipientItemAndExecute() public {
        // Setup
        FlowTypes.RecipientMetadata memory metadata = FlowTypes.RecipientMetadata({
            title: "Flow Recipient",
            description: "Test Flow Recipient",
            image: "ipfs://image",
            tagline: "Test Tagline",
            url: "https://example.com"
        });
        bytes memory itemData = abi.encode(address(0), metadata, FlowTypes.RecipientType.FlowContract);

        uint256 arbitratorCost = arbitrator.arbitrationCost(bytes(""));

        // Approve GeneralizedTCR to spend tokens
        vm.prank(requester);
        erc20Token.approve(address(flowTCR), SUBMISSION_BASE_DEPOSIT + arbitratorCost);

        // Add Flow recipient item
        vm.prank(requester);
        bytes32 itemID = flowTCR.addItem(itemData);

        // Verify item is in pending state
        (bytes memory data, IGeneralizedTCR.Status status, uint256 numberOfRequests) = flowTCR.getItemInfo(itemID);
        assertEq(uint256(status), uint256(IGeneralizedTCR.Status.RegistrationRequested));

        // Advance time past challenge period
        vm.warp(block.timestamp + flowTCR.challengePeriodDuration() + 1);

        // Execute request
        flowTCR.executeRequest(itemID);

        // Verify item is now registered
        (data, status, numberOfRequests) = flowTCR.getItemInfo(itemID);
        assertEq(uint256(status), uint256(IGeneralizedTCR.Status.Registered));

        // Verify Flow recipient is added
        FlowTypes.FlowRecipient memory storedRecipient = flow.getRecipientById(itemID);
        assertEq(uint8(storedRecipient.recipientType), uint8(FlowTypes.RecipientType.FlowContract));
        assertFalse(storedRecipient.removed);
        assertNotEq(storedRecipient.recipient, address(0));

        // ensure incoming flow rate of reward pool is set correctly
        assertGt(flow.getManagerRewardPoolFlowRate(), 0);
        // ensure outgoing flow rate of reward pool is set correctly
        assertGt(RewardPool(flow.managerRewardPool()).getTotalFlowRate(), 0);
    }
}
