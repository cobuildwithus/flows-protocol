// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { CustomFlow } from "../../src/flows/CustomFlow.sol";
import { ICustomFlow, IFlow } from "../../src/interfaces/IFlow.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";
import { IAllocationStrategy } from "../../src/interfaces/IAllocationStrategy.sol";
import { IChainalysisSanctionsList } from "../../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { SingleAllocatorStrategy } from "../../src/allocation-strategies/SingleAllocatorStrategy.sol";
import { IRewardPool } from "../../src/interfaces/IRewardPool.sol";
import { RewardPool } from "../../src/token-issuance/RewardPool.sol";

import { WitnessCacheHelper } from "../helpers/WitnessCacheHelper.sol";

contract GasAllocateBaseForkNewFlowTest is Test, WitnessCacheHelper {
    function testGas_Allocate_NewCustomFlow_170Recipients() public {
        // Require Base RPC and SuperToken to be configured
        string memory baseUrl = vm.envOr("RPC_BASE", string(""));
        if (bytes(baseUrl).length == 0) {
            emit log("Skipping: RPC_BASE not set");
            return;
        }
        address superTokenAddr = vm.envOr("SUPER_TOKEN", address(0xD04383398dD2426297da660F9CCA3d439AF9ce1b));

        vm.createSelectFork(baseUrl);

        address manager = address(0x1998);

        // Deploy CustomFlow implementation and proxy (uninitialized)
        address flowImpl = address(new CustomFlow());
        address flowProxy = address(new ERC1967Proxy(flowImpl, ""));

        // Deploy RewardPool implementation + proxy, initialize with flowProxy as funder
        address rewardPoolImpl = address(new RewardPool());
        address rewardPoolProxy = address(new ERC1967Proxy(rewardPoolImpl, ""));
        IRewardPool(rewardPoolProxy).initialize(ISuperToken(superTokenAddr), manager, flowProxy, manager);

        // Deploy SingleAllocatorStrategy implementation + proxy, initialize with manager as allocator
        address stratImpl = address(new SingleAllocatorStrategy());
        address stratProxy = address(new ERC1967Proxy(stratImpl, ""));
        vm.prank(manager);
        SingleAllocatorStrategy(stratProxy).initialize(manager, manager);

        IAllocationStrategy[] memory strategies = new IAllocationStrategy[](1);
        strategies[0] = IAllocationStrategy(stratProxy);

        // Initialize the flow proxy
        IFlow.FlowParams memory flowParams = IFlow.FlowParams({
            baselinePoolFlowRatePercent: 0,
            managerRewardPoolFlowRatePercent: 0,
            bonusPoolQuorumBps: 1e6
        });
        FlowTypes.RecipientMetadata memory flowMetadata = FlowTypes.RecipientMetadata({
            title: "Base Fork Flow",
            description: "Flow deployed in Base fork test",
            image: "ipfs://image",
            tagline: "",
            url: ""
        });

        vm.prank(manager);
        ICustomFlow(flowProxy).initialize({
            initialOwner: manager,
            superToken: superTokenAddr,
            flowImpl: flowImpl,
            manager: manager,
            managerRewardPool: rewardPoolProxy,
            parent: address(0),
            connectPoolAdmin: address(0),
            flowParams: flowParams,
            metadata: flowMetadata,
            sanctionsOracle: IChainalysisSanctionsList(address(0)),
            strategies: strategies
        });

        // Manager adds 170 recipients
        FlowTypes.RecipientMetadata memory recipientMetadata = FlowTypes.RecipientMetadata({
            title: "Recipient",
            description: "Recipient desc",
            image: "ipfs://img",
            tagline: "",
            url: ""
        });

        vm.startPrank(manager);
        bytes32[] memory recipientIds = new bytes32[](170);
        for (uint256 i = 0; i < 170; i++) {
            address recipient = address(uint160(1000 + i));
            bytes32 rid = keccak256(abi.encodePacked(recipient));
            recipientIds[i] = rid;
            CustomFlow(flowProxy).addRecipient(rid, recipient, recipientMetadata);
        }
        vm.stopPrank();

        // Prepare 100% allocation split across 170 recipients
        uint32[] memory percentAllocations = new uint32[](170);
        uint32 baseShare = uint32(uint256(1_000_000) / 170);
        uint256 runningTotal = 0;
        for (uint256 i = 0; i < 169; i++) {
            percentAllocations[i] = baseShare;
            runningTotal += baseShare;
        }
        percentAllocations[169] = uint32(1_000_000 - runningTotal);

        // Build allocation input: single strategy, single key
        bytes[][] memory allocationData = new bytes[][](1);
        allocationData[0] = new bytes[](1);
        allocationData[0][0] = hex"";

        // First allocation (establish previous commit)
        bytes[][] memory witnesses = _buildWitnessesForStrategy(manager, allocationData, stratProxy);
        vm.prank(manager);
        CustomFlow(flowProxy).allocate(allocationData, witnesses, recipientIds, percentAllocations);
        _updateWitnessCacheForStrategy(manager, allocationData, stratProxy, recipientIds, percentAllocations);

        // Second allocation with slight tweak
        uint32[] memory percentAllocations2 = new uint32[](170);
        for (uint256 i = 0; i < 170; i++) percentAllocations2[i] = percentAllocations[i];
        if (percentAllocations2[0] > 0) {
            percentAllocations2[0] -= 1;
            percentAllocations2[1] += 1;
        }

        vm.pauseGasMetering();
        witnesses = _buildWitnessesForStrategy(manager, allocationData, stratProxy);
        vm.resumeGasMetering();

        uint256 gasBefore = gasleft();
        vm.prank(manager);
        CustomFlow(flowProxy).allocate(allocationData, witnesses, recipientIds, percentAllocations2);
        uint256 gasUsed1 = gasBefore - gasleft();
        _updateWitnessCacheForStrategy(manager, allocationData, stratProxy, recipientIds, percentAllocations2);

        emit log_named_uint("Witness allocate(170 recipients) gas", gasUsed1);

        // Third allocation with another tweak, measure again
        uint32[] memory percentAllocations3 = new uint32[](170);
        for (uint256 i = 0; i < 170; i++) percentAllocations3[i] = percentAllocations2[i];
        if (percentAllocations3[2] > 0) {
            percentAllocations3[2] -= 1;
            percentAllocations3[3] += 1;
        }

        vm.pauseGasMetering();
        witnesses = _buildWitnessesForStrategy(manager, allocationData, stratProxy);
        vm.resumeGasMetering();

        gasBefore = gasleft();
        vm.prank(manager);
        CustomFlow(flowProxy).allocate(allocationData, witnesses, recipientIds, percentAllocations3);
        uint256 gasUsed2 = gasBefore - gasleft();

        emit log_named_uint("Witness allocate(170 recipients) gas (second)", gasUsed2);
    }
}
