// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { FlowTCRTest } from "./FlowTCR.t.sol";
import { Flow } from "../../src/Flow.sol";
import { CustomFlow } from "../../src/flows/CustomFlow.sol";
import { FlowDeployer } from "../../src/FlowDeployer.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";
import { IFlowDeployer } from "../../src/interfaces/IFlowDeployer.sol";
import { IFlow } from "../../src/interfaces/IFlow.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TCRFundFlowTest is FlowTCRTest {
    // function test_storage_issue() public {
    //     // uint256 blockNumber = 138002442;
    //     vm.createSelectFork(vm.rpcUrl("base"));
    //     address flowDeployer = address(0x62953560766Ac1be810e6ef13aB3736F8e2C8a41);
    //     address newImpl = address(new FlowDeployer());
    //     vm.startPrank(0x289715fFBB2f4b482e2917D2f183FeAb564ec84F);
    //     FlowDeployer(flowDeployer).upgradeTo(newImpl);
    //     FlowDeployer deployer = FlowDeployer(flowDeployer);
    //     // Set up deploy params with actual values
    //     address manager = address(0xb9d58f3575BF264cf705C15fcFa06EB4AFDcEa64);
    //     address underlyingERC20 = address(0x051024B653E8ec69E72693F776c41C2A9401FB07); // USDC on Base
    //     address allocator = address(0x279adb5201ee14F717560cfAA560E4648f037dc3);
    //     IFlow.FlowParams memory flowParams = IFlow.FlowParams({
    //         baselinePoolFlowRatePercent: 0,
    //         managerRewardPoolFlowRatePercent: 0,
    //         bonusPoolQuorumBps: 1000000
    //     });
    //     FlowTypes.RecipientMetadata memory metadata = FlowTypes.RecipientMetadata({
    //         title: "Cobuilders Flow",
    //         description: "Pay cobuilders for their efforts",
    //         image: "",
    //         tagline: "Cobuild funding flow",
    //         url: ""
    //     });
    //     IFlowDeployer.DeployParams memory params = IFlowDeployer.DeployParams({
    //         manager: manager,
    //         underlyingERC20: underlyingERC20,
    //         allocator: allocator,
    //         flowParams: flowParams,
    //         metadata: metadata
    //     });
    //     // Deploy flow
    //     (address flow, address strategy) = deployer.deployFlow(params);
    //     assertTrue(flow != address(0), "flow should be deployed");
    //     assertTrue(strategy != address(0), "strategy should be deployed");
    // }
}
