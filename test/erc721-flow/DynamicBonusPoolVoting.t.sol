// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { ERC721FlowTest } from "./ERC721Flow.t.sol";
import { IFlow, ICustomFlow } from "../../src/interfaces/IFlow.sol";
import { CustomFlow } from "../../src/flows/CustomFlow.sol";
import { Flow } from "../../src/Flow.sol";
import { console } from "forge-std/console.sol";

/**
 * @title DynamicBonusFlowRateTest
 * @notice This test suite focuses on verifying the dynamic bonus flow rate
 *         logic that scales linearly based on quorum. We assume we already
 *         have a Flow instance deployed (in setUp) with an ERC721 voting token.
 */
contract DynamicBonusPoolVotingTest is ERC721FlowTest {
    // We'll define a new quorum for these tests
    uint32 public constant QUORUM_BPS = 400000; // 40% of total supply

    address public voter1 = address(0xA1);
    address public voter2 = address(0xA2);

    uint256 public tokenId1 = 1;
    uint256 public tokenId2 = 2;

    address recipient = address(3);
    address recipient2 = address(4);

    uint32 defaultBaselineFlowRatePercent = 200000; // 20%
    uint32 defaultManagerRewardFlowRatePercent = 100000; // 10%

    function setUp() public override {
        super.setUp();

        // Mint some ERC721 tokens to different voters
        nounsToken.mint(voter1, tokenId1);
        nounsToken.mint(voter2, tokenId2);

        // Set baseline = 20%, manager = 10%. That leaves 70% leftover as the "max possible bonus."
        vm.prank(flow.owner());
        flow.setBaselineFlowRatePercent(defaultBaselineFlowRatePercent);
        vm.prank(flow.owner());
        flow.setManagerRewardFlowRatePercent(defaultManagerRewardFlowRatePercent);

        // Now set the bonus quorum to 40%
        vm.prank(flow.owner());
        flow.setBonusPoolQuorum(QUORUM_BPS);

        // Add two recipients so we can test distribution
        vm.startPrank(manager);
        bytes32 recipientId = keccak256(abi.encodePacked(recipient));
        bytes32 recipientId2 = keccak256(abi.encodePacked(recipient2));
        flow.addRecipient(recipientId, recipient, recipientMetadata);
        flow.addRecipient(recipientId2, recipient2, recipientMetadata);
        vm.stopPrank();
    }

    /**
     * @notice Helper to cast full votes from a certain address for a given token.
     * @param voter The address who owns the token
     * @param tokenId The token id
     * @param recipientAddr The recipient to vote for (100%)
     */
    function _voteAllToSingleRecipient(address voter, uint256 tokenId, address recipientAddr) internal {
        // The manager must have added the recipient
        vm.startPrank(flow.manager());
        bytes32 recId = keccak256(abi.encodePacked(recipientAddr));
        flow.addRecipient(recId, recipientAddr, recipientMetadata);
        vm.stopPrank();

        // do 100% vote to that single recipient
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = recId;
        uint32[] memory allocs = new uint32[](1);
        allocs[0] = 1e6; // 100%
        uint256[] memory tokens = new uint256[](1);
        tokens[0] = tokenId;

        allocateTokensWithWitnessHelper(voter, tokens, ids, allocs);
    }

    /**
     * @dev We measure the actual flow distribution by calling:
     *        - flow.getTotalFlowRate() => total
     *        - flow.baselinePool().getTotalFlowRate() => baseline
     *        - flow.bonusPool().getTotalFlowRate() => bonus
     *        - flow.getManagerRewardPoolFlowRate() => manager
     */
    function _getFlowRates() internal view returns (int96 total, int96 baseline, int96 bonus, int96 managerFlow) {
        total = flow.getTotalFlowRate();
        managerFlow = flow.getManagerRewardPoolFlowRate();
        baseline = flow.baselinePool().getTotalFlowRate();
        bonus = flow.bonusPool().getTotalFlowRate();
    }

    /**
     * @notice Test scenario: No one votes => we see baseline at 90%, manager at 10%, bonus at 0
     */
    function testNoVotes() public {
        (int96 total, int96 baseline, int96 bonus, int96 managerFlow) = _getFlowRates();

        // manager is ~10% of total
        int96 managerExpected = (total * 10e4) / 1e6;
        assertEq(managerFlow, managerExpected, "manager portion ~ 10%");

        // leftover after manager
        int96 remaining = total - managerFlow;

        assertApproxEqRel(baseline, remaining, 1e14, "baseline portion ~ 80% of leftover");

        // bonus should be leftover minus baseline => 70% ( leftover * (1- 0.2) = 80% leftover?
        // But from your code, it might be leftover * 80%. Let’s do an approximate check:
        int96 bonusExpected = 0;
        assertEq(bonus, bonusExpected, "bonus portion is leftover after baseline");

        // Check that the two recipients have the same total flow from the bonus pool
        // because no one has cast any vote weighting them differently.
        int96 recipient1FlowRate = flow.getMemberTotalFlowRate(recipient);
        int96 recipient2FlowRate = flow.getMemberTotalFlowRate(recipient2);
        assertEq(recipient1FlowRate, recipient2FlowRate, "Should have same flow rate since no votes");
    }

    /**
     * @notice Test partial votes: If only half of the quorum is reached, we should see half of leftover used by bonus.
     */
    function testPartialVotes() public {
        // total supply is 2 from setUp.
        // Quorum = 40% of 2 => 0.8 => If only 1 token votes, ratio= 1/0.8=1.25 => that actually meets full quorum.
        // So let's mint 3 more to ensure partial scenario => total supply=5 => we need 2 votes for full quorum,
        // only 1 is 1/2 => partial bonus.

        nounsToken.mint(address(0x999), 3);
        nounsToken.mint(address(0x999), 4);
        nounsToken.mint(address(0x999), 5);

        _voteAllToSingleRecipient(voter1, tokenId1, address(0xABC));

        uint256 activeVoteWeight = flow.totalActiveAllocationWeight();
        uint256 tokenVoteWeight = tokenVoteWeight();

        // Only 1 token votes => ratio=1 active /2 needed =>0.5 => half leftover
        assertEq(activeVoteWeight, tokenVoteWeight, "minted should be 1");

        (int96 total, int96 baseline, int96 bonus, int96 managerFlow) = _getFlowRates();

        // manager ~ 10% of total
        int96 managerExpected = (total * 10e4) / 1e6;
        assertApproxEqRel(managerFlow, managerExpected, 1e14, "manager portion ~10%");

        // leftover = total - managerFlow
        int96 leftover = total - managerFlow;

        // baseline should be 20% of leftover, bonus 80%
        int96 baselineExpected = (leftover * 20e4) / 1e6;
        int96 bonusExpectedFull = leftover - baselineExpected;

        // Since ratio = 0.5 (half quorum), bonus is half of its full potential
        int96 bonusExpected = bonusExpectedFull / 2;
        int96 baselineAdjusted = leftover - bonusExpected;

        // Check sum baseline + bonus + manager equals total
        assertApproxEqRel(baseline + bonus + managerFlow, total, 1e14, "sum baseline+bonus+manager= total");

        assertApproxEqRel(bonus, bonusExpected, 1e14, "bonus adjusted correctly for partial quorum");
    }

    /**
     * @notice Test full quorum: 1 token (since total supply=2) meets or exceeds 40% => full leftover to bonus.
     */
    function testFullQuorum() public {
        // If 1 token votes => ratio=1 /0.8 => clamp to 1 => full leftover used for bonus

        _voteAllToSingleRecipient(voter1, tokenId1, address(0xAAA));

        (int96 total, int96 baseline, int96 bonus, int96 managerFlow) = _getFlowRates();

        // manager ~ 10%
        int96 managerExpected = (total * 10e4) / 1e6;
        assertApproxEqRel(managerFlow, managerExpected, 1e14, "manager portion ~10%");

        // leftover= total - manager
        int96 leftover = total - managerFlow;

        // baseline fraction => leftover * 20%
        int96 baseFraction = (leftover * 200000) / 1e6;
        // if ratio=1 => bonus gets leftover - baseFraction
        int96 bonusExpected = leftover - baseFraction;

        assertApproxEqRel(baseline, baseFraction, 1e14, "baseline is correct fraction");
        assertApproxEqRel(bonus, bonusExpected, 1e14, "bonus uses leftover");
        assertApproxEqRel(baseline + bonus + managerFlow, total, 1e14, "sum should match total");
    }

    /**
     * @notice test exceeding full quorum => we clamp ratio to 100%.
     */
    function testExceedQuorumRatio() public {
        // If 2 tokens vote but quorum=0.8 => ratio= 2/0.8=2.5 => clamp to 1 => same as full quorum

        _voteAllToSingleRecipient(voter1, tokenId1, address(0xAAA));
        _voteAllToSingleRecipient(voter2, tokenId2, address(0xBBB));

        (int96 total, int96 baseline, int96 bonus, int96 managerFlow) = _getFlowRates();

        // leftover = total - manager
        int96 leftover = total - managerFlow;
        int96 baseFraction = (leftover * 200000) / 1e6;
        int96 bonusExpected = leftover - baseFraction;

        assertApproxEqRel(baseline, baseFraction, 1e14, "baseline fraction correct");
        assertApproxEqRel(bonus, bonusExpected, 1e14, "bonus uses leftover fully");
    }

    /**
     * @notice Test changing the quorum mid-run.
     */
    function testUpdateQuorumMidRun() public {
        // Initial quorum is 40% (400000), total supply = 2 tokens
        // 1 token votes => 1 / (0.4 * 2) = 1.25 => clamp to 1 => full leftover to bonus
        _voteAllToSingleRecipient(voter1, tokenId1, address(0xAAA));

        (int96 total, int96 baseline, int96 bonus, int96 managerFlow) = _getFlowRates();

        // manager ~ 10%
        int96 managerExpected = (total * 100000) / 1e6;
        assertApproxEqRel(managerFlow, managerExpected, 1e14, "manager portion ~10%");

        // leftover = total - manager
        int96 leftover = total - managerFlow;

        // baseline fraction => leftover * 20%
        int96 baseFraction = (leftover * 200000) / 1e6;
        int96 bonusExpected = leftover - baseFraction;

        assertApproxEqRel(baseline, baseFraction, 1e14, "baseline is 20% leftover");
        assertApproxEqRel(bonus, bonusExpected, 1e14, "bonus uses leftover (full quorum met)");

        // now set quorum to 80% (800000) => ratio for 1 token out of total=2 => 1 / (0.8*2=1.6) => ~0.625 => partial quorum
        vm.prank(flow.owner());
        flow.setBonusPoolQuorum(800000);

        (total, baseline, bonus, managerFlow) = _getFlowRates();

        // leftover recalculated after quorum update
        leftover = total - managerFlow;

        // baseline fraction remains 20% of leftover
        baseFraction = (leftover * 200000) / 1e6;

        // ratio = 0.625 => bonus = (leftover - baseFraction) * 0.625
        int96 maxBonusFlowRate = leftover - baseFraction;
        int96 bonusExpected2 = (maxBonusFlowRate * 625) / 1000;
        int96 baselineExpected2 = leftover - bonusExpected2;

        assertApproxEqRel(bonus, bonusExpected2, 1e14, "bonus adjusted correctly for partial quorum");
        assertApproxEqRel(baseline, baselineExpected2, 1e14, "baseline adjusted correctly after quorum update");
        assertApproxEqRel(baseline + bonus + managerFlow, total, 1e14, "sum should match total after quorum update");
    }
}
