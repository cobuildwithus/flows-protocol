// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { FlowTCRTest } from "./FlowTCR.t.sol";

import { NounsFlow } from "../../src/NounsFlow.sol";
import { Flow } from "../../src/Flow.sol";

contract TCRFundFlowTest is FlowTCRTest {
    // add 4 items, vote and execute using requester

    function test_issue() public {
        uint256 blockNumber = 28156695;
        vm.createSelectFork(vm.rpcUrl("base"), blockNumber);

        address deployedFlow = address(0x0D4a25d07015ec7BdebF78f2937A617A86AF27Ff);

        address nounsFlowImpl = address(new NounsFlow());
        // upgrade flow to current implementation
        vm.prank(Flow(deployedFlow).owner());
        Flow(deployedFlow).upgradeTo(nounsFlowImpl);

        address[] memory staleAddresses = new address[](17);
        staleAddresses[0] = 0x2B7982045E5f0C1F270228c5128986dC3F5C45dc;
        staleAddresses[1] = 0x03bBF8812B0635774Bdf344C0DE33d94a057aA28;
        staleAddresses[2] = 0xbb78e3081F96ed9cf4d5C384D2307F6ec9174f11;
        staleAddresses[3] = 0xb93213a7a9a920f2450BCBca72AB8B84e4158f2e;
        staleAddresses[4] = 0xA5F83407e6c42a2093BC9A05ee799d8E5da8dbD6;
        staleAddresses[5] = 0x8dE3a7fa22afAB97560824cB2fb97729db56546C;
        staleAddresses[6] = 0x8CA1dC53e1c6c0D93D31847C8dB86Dd405F4AD64;
        staleAddresses[7] = 0x3e26bDf08040aAFf4f4eE28522124a1B6f6b4F7D;
        staleAddresses[8] = 0xeE35f783F9d3983B4362BccE51a2078d207dD465;
        staleAddresses[9] = 0x5A433EBBcC42C3fFE9e8FCd232E14293076e6012;
        staleAddresses[10] = 0x67a61Ee656b069a95ff06132626c6626B3a6122f;
        staleAddresses[11] = 0x7D86677e1ac13B1Cae5F92FbD4921b9ba670283C;
        staleAddresses[12] = 0x2f0Bf4037aC2c17E3f71decE1348918941295078;
        staleAddresses[13] = 0x142423e651517c85473A878e39423388848EAf5F;
        staleAddresses[14] = 0xD77028b1837c74910E81D87D292FC7683b83653c;
        staleAddresses[15] = 0x051663C6dA83A9da5205b9bdeA38fBF59797435d;
        staleAddresses[16] = 0x41718e49a262B5e13bf36C655E0E52713bb7d973;

        vm.prank(Flow(deployedFlow).owner());
        Flow(deployedFlow).fixCorruptedSets(staleAddresses);

        vm.prank(Flow(deployedFlow).owner());
        Flow(deployedFlow).backfillActiveVotes(28000 * 1e18);

        uint256 childFlowsLength = Flow(deployedFlow).getChildFlows().length;
        assertEq(childFlowsLength, 17);

        uint256 outOfSync = Flow(deployedFlow).childFlowRatesOutOfSync();
        assertEq(outOfSync, 0);

        vm.prank(Flow(deployedFlow).owner());
        Flow(deployedFlow).setBonusPoolQuorum(50000);

        // vm.prank(Flow(deployedFlow).owner());
        // NounsFlow(deployedFlow).updateVerifier(0x08009Fcf85aF4724589706a22DDF2844607b8853);
    }
}
