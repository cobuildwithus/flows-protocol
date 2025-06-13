// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { ERC20VotesArbitrator } from "../../src/tcr/ERC20VotesArbitrator.sol";
import { ERC20VotesMintable } from "../../src/base/erc20/ERC20VotesMintable.sol";
import { FlowTCR } from "../../src/tcr/FlowTCR.sol";
import { IArbitrable } from "../../src/tcr/interfaces/IArbitrable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FlowTCRTest } from "../tcr/FlowTCR.t.sol";

contract ERC20VotesArbitratorTest is FlowTCRTest {
    address public voter1;
    address public voter2;
    address public voter3;

    function setUp() public override {
        super.setUp();
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        voter3 = makeAddr("voter3");

        // Mint tokens to test addresses
        erc20Token.mint(voter1, 1000 ether);
        erc20Token.mint(voter2, 1000 ether);
        erc20Token.mint(voter3, 1000 ether);
        erc20Token.mint(requester, 1000 ether);
        erc20Token.mint(challenger, 1000 ether);

        // Approve arbitrator to spend tokens
        vm.prank(voter1);
        erc20Token.approve(address(flowTCR), type(uint256).max);
        vm.prank(voter2);
        erc20Token.approve(address(flowTCR), type(uint256).max);
        vm.prank(voter3);
        erc20Token.approve(address(flowTCR), type(uint256).max);
        vm.prank(requester);
        erc20Token.approve(address(flowTCR), type(uint256).max);
        vm.prank(challenger);
        erc20Token.approve(address(flowTCR), type(uint256).max);
    }

    function commitVote(uint256 disputeID, address voter, uint256 choice, string memory reason, bytes32 salt) internal {
        bytes32 commitHash = keccak256(abi.encode(choice, reason, salt));
        vm.prank(voter);
        arbitrator.commitVote(disputeID, commitHash);
    }

    function revealVote(uint256 disputeID, address voter, uint256 choice, string memory reason, bytes32 salt) internal {
        vm.prank(voter);
        arbitrator.revealVote(disputeID, voter, choice, reason, salt);
    }

    // Helper function to submit an item and challenge it
    function submitItemAndChallenge(
        bytes memory _itemData,
        address _requester,
        address _challenger
    ) internal returns (bytes32 itemID, uint256 disputeID) {
        itemID = submitItem(_itemData, _requester);
        disputeID = challengeItem(itemID, _challenger);
    }
}
