// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { SingleAllocatorFlowTestBase } from "./SingleAllocatorFlow.t.sol";
import { IFlow } from "../../../src/interfaces/IFlow.sol";
import { FlowTypes } from "../../../src/storage/FlowStorage.sol";
import { SingleAllocatorStrategy } from "../../../src/allocation-strategies/SingleAllocatorStrategy.sol";

contract BasicSingleAllocator is SingleAllocatorFlowTestBase {
    // ────────────────────────────────────────────────
    //                     Tests
    // ────────────────────────────────────────────────

    function testAllocateHappyPath() public {
        address r1 = address(0x111);
        address r2 = address(0x222);
        bytes32 id1 = keccak256("r1");
        bytes32 id2 = keccak256("r2");
        _addRecipient(id1, r1);
        _addRecipient(id2, r2);

        uint32[] memory bps = new uint32[](2);
        bps[0] = 600_000; // 60%
        bps[1] = 400_000; // 40%

        bytes32[] memory ids = new bytes32[](2);
        ids[0] = id1;
        ids[1] = id2;

        bytes[][] memory allocData = _defaultAllocationData();

        allocateWithWitnessHelper(_allocator, allocData, ids, bps);

        assertEq(_flow.totalActiveAllocationWeight(), SingleAllocatorStrategy(_strategyProxy).VIRTUAL_WEIGHT());
    }

    function testAllocateUnauthorizedReverts() public {
        address r1 = address(0x123);
        bytes32 id1 = keccak256("r1");
        _addRecipient(id1, r1);

        uint32[] memory bps = new uint32[](1);
        bps[0] = 1_000_000;
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = id1;
        bytes[][] memory allocData = _defaultAllocationData();

        allocateWithWitnessHelper(
            _attacker,
            allocData,
            ids,
            bps,
            abi.encodeWithSelector(IFlow.NOT_ABLE_TO_ALLOCATE.selector)
        );
    }

    function testAllocatorChangeEffects() public {
        bytes32 id = keccak256("r1");
        _addRecipient(id, address(0x444));

        uint32[] memory bps = new uint32[](1);
        bps[0] = 1_000_000;
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = id;
        bytes[][] memory allocData = _defaultAllocationData();

        vm.prank(_manager);
        SingleAllocatorStrategy(_strategyProxy).changeAllocator(_newAllocator);

        allocateWithWitnessHelper(
            _allocator,
            allocData,
            ids,
            bps,
            abi.encodeWithSelector(IFlow.NOT_ABLE_TO_ALLOCATE.selector)
        );

        allocateWithWitnessHelper(_newAllocator, allocData, ids, bps);
    }

    function testTotalAllocationWeightView() public {
        assertEq(_flow.totalAllocationWeight(), 0);

        bytes32 id = keccak256("r2");
        _addRecipient(id, address(0x555));

        uint32[] memory bps = new uint32[](1);
        bps[0] = 1_000_000;
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = id;
        bytes[][] memory allocData = _defaultAllocationData();

        allocateWithWitnessHelper(_allocator, allocData, ids, bps);

        assertEq(_flow.totalAllocationWeight(), 0);
    }

    // Additional edge-case: allocationData length mismatch
    function testAllocationDataLengthMismatch() public {
        bytes32 id = keccak256("rx");
        _addRecipient(id, address(0x999));

        uint32[] memory bps = new uint32[](1);
        bps[0] = 1_000_000;
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = id;
        // Make allocationData 0 length → mismatch with strategies length (1)
        bytes[][] memory badAllocData = new bytes[][](0);

        allocateWithWitnessHelper(
            _allocator,
            badAllocData,
            ids,
            bps,
            abi.encodeWithSelector(IFlow.ALLOCATION_LENGTH_MISMATCH.selector)
        );
    }
}
