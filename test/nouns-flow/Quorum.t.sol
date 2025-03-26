pragma solidity ^0.8.28;

import { NounsFlowTest } from "./NounsFlow.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract QuorumTest is NounsFlowTest {
    function test_totalTokenSupplyVoteWeight() public {
        _setUp();
        vm.createSelectFork(vm.rpcUrl("base"));

        uint256 firstAuctionStartSeconds = 1628399590;
        uint256 daysSinceStart = (block.timestamp - firstAuctionStartSeconds) / 1 days;
        uint256 founderNouns = (daysSinceStart / 10) + 1;
        uint256 expectedTotalNouns = daysSinceStart + founderNouns;
        uint256 expectedVoteWeight = expectedTotalNouns * flowParams.tokenVoteWeight;

        uint256 actualVoteWeight = flow.totalTokenSupplyVoteWeight();

        assertEq(actualVoteWeight, expectedVoteWeight, "Total token supply vote weight mismatch");
    }

    function test_againstNounsContract() public {
        _setUp();
        vm.createSelectFork(vm.rpcUrl("base"));

        uint256 computedVoteWeight = flow.totalTokenSupplyVoteWeight();
        uint256 tokenVoteWeight = flowParams.tokenVoteWeight;

        uint256 expectedTotalNouns = computedVoteWeight / tokenVoteWeight;

        vm.createSelectFork(vm.rpcUrl("mainnet"));

        address nounsToken = address(0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03);

        // also test by calling the token contract directly
        uint256 tokenSupply = IERC20(nounsToken).totalSupply();
        uint256 tolerance = (expectedTotalNouns * 2) / 100; // 2% tolerance
        uint256 difference = tokenSupply > expectedTotalNouns
            ? tokenSupply - expectedTotalNouns
            : expectedTotalNouns - tokenSupply;
        assertLe(difference, tolerance, "Token supply mismatch exceeds 2% tolerance");
    }
}
