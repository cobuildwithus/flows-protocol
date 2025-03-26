// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { FlowTCRTest } from "./FlowTCR.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { NounsFlow } from "../../src/NounsFlow.sol";
import { Flow } from "../../src/Flow.sol";
import { IFlow, INounsFlow } from "../../src/interfaces/IFlow.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { NounsFlow } from "../../src/NounsFlow.sol";
import { IStateProof } from "../../src/interfaces/IStateProof.sol";

contract TCRFundFlowTest is FlowTCRTest {
    // add 4 items, vote and execute using requester

    function test_issue() public {
        uint256 blockNumber = 21347817;
        vm.createSelectFork(vm.rpcUrl("base"), blockNumber);

        address deployedFlow = address(0x816897059Ce5938C16A2770Bf9BA9A7caA487639);

        address nounsFlowImpl = address(new NounsFlow());
        // upgrade flow to current implementation
        vm.prank(0x289715fFBB2f4b482e2917D2f183FeAb564ec84F);
    }
}
