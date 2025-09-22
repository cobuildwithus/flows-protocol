// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { CustomFlow } from "../../src/flows/CustomFlow.sol";
import { IAllocationStrategy } from "../../src/interfaces/IAllocationStrategy.sol";

contract GasAllocateBaseForkTest is Test {
    using stdJson for string;

    function testGas_Allocate_OnBase_CustomFlow() public {
        // Allow skipping if no Base RPC is configured
        string memory baseUrl = vm.envOr("RPC_BASE", string(""));
        if (bytes(baseUrl).length == 0) {
            emit log("Skipping: RPC_BASE not set");
            return;
        }
        vm.createSelectFork(baseUrl);

        address flowAddr = address(0xC5999aACbc59bC07f589d3af5Cd3c9aaBeB6B939);

        // upgrade to new flow
        address newCustomFlow = address(new CustomFlow());
        vm.prank(address(0x289715fFBB2f4b482e2917D2f183FeAb564ec84F));
        CustomFlow(flowAddr).upgradeTo(newCustomFlow);

        address sender = address(0x279adb5201ee14F717560cfAA560E4648f037dc3);

        // Load large args from JSON to keep the test readable
        string memory json = vm.readFile("test/data/allocate_base_customflow.json");

        bytes32[] memory recipientIds = abi.decode(vm.parseJson(json, ".recipientIds"), (bytes32[]));
        uint32[] memory percentAllocations = abi.decode(vm.parseJson(json, ".percentAllocations"), (uint32[]));
        bytes memory prevWitness = json.readBytes(".prevWitness");

        // Build allocation inputs (single strategy, single key)
        bytes[][] memory allocationData = new bytes[][](1);
        allocationData[0] = new bytes[](1);
        allocationData[0][0] = hex"";

        bytes[][] memory prevAllocationWitnesses = new bytes[][](1);
        prevAllocationWitnesses[0] = new bytes[](1);
        // Normalize witness to sorted ids/bps as required by FlowAllocations
        {
            (uint256 w, bytes32[] memory ids, uint32[] memory bps) = abi.decode(
                prevWitness,
                (uint256, bytes32[], uint32[])
            );
            if (ids.length > 1) {
                _qsortPairs(ids, bps, int256(0), int256(ids.length - 1));
            }
            prevWitness = abi.encode(w, ids, bps);
        }
        prevAllocationWitnesses[0][0] = prevWitness;

        // Compute expected commit from provided witness and roll fork if needed
        (uint256 prevWeight, bytes32[] memory prevIds, uint32[] memory prevBps) = abi.decode(
            prevWitness,
            (uint256, bytes32[], uint32[])
        );

        // Fetch strategy and key
        IAllocationStrategy[] memory strats = CustomFlow(flowAddr).strategies();
        address strategyAddr = address(strats[0]);
        uint256 key = IAllocationStrategy(strategyAddr).allocationKey(sender, allocationData[0][0]);

        bytes32 expectedCommit = _hashAllocCanonical(prevWeight, prevIds, prevBps);
        bytes32 currentCommit = CustomFlow(flowAddr).getAllocationCommitment(strategyAddr, key);

        if (currentCommit != expectedCommit) {
            // Try to roll back to a recent block where the commit matches the provided witness
            uint256 start = block.number;
            bool matched = false;
            // coarse then fine search
            for (uint256 i = 1; i <= 40 && !matched; i++) {
                uint256 target = start > i * 2500 ? start - i * 2500 : 1;
                vm.rollFork(target);
                currentCommit = CustomFlow(flowAddr).getAllocationCommitment(strategyAddr, key);
                if (currentCommit == expectedCommit) matched = true;
            }
            if (!matched) {
                // small step fallback (500 blocks up to 20k)
                for (uint256 i = 1; i <= 40 && !matched; i++) {
                    uint256 target = start > i * 500 ? start - i * 500 : 1;
                    vm.rollFork(target);
                    currentCommit = CustomFlow(flowAddr).getAllocationCommitment(strategyAddr, key);
                    if (currentCommit == expectedCommit) matched = true;
                }
            }
            emit log_named_bytes32("expectedCommit", expectedCommit);
            emit log_named_bytes32("onchainCommit", currentCommit);
        }

        vm.startPrank(sender);

        vm.pauseGasMetering();
        vm.resumeGasMetering();

        // Ensure sorted & unique, as required by FlowAllocations
        {
            // sort ids/bps in tandem by ids asc
            require(recipientIds.length == percentAllocations.length, "ids/bps mismatch");
            if (recipientIds.length > 1) {
                _qsortPairs(recipientIds, percentAllocations, int256(0), int256(recipientIds.length - 1));
            }
        }

        uint256 gasBefore = gasleft();
        bool ok;
        try CustomFlow(flowAddr).allocate(allocationData, prevAllocationWitnesses, recipientIds, percentAllocations) {
            ok = true;
        } catch {
            ok = false;
        }
        uint256 gasUsed = gasBefore - gasleft();

        vm.pauseGasMetering();
        vm.stopPrank();

        emit log_named_uint("Base fork allocate() gas", gasUsed);
        emit log_named_string("Base fork allocate() status", ok ? "success" : "reverted");
    }

    // Re-implement canonical hash from FlowAllocations for witness verification
    function _hashAllocCanonical(
        uint256 weight,
        bytes32[] memory ids,
        uint32[] memory bps
    ) internal pure returns (bytes32) {
        uint256 n = ids.length < bps.length ? ids.length : bps.length;
        if (n == 0) return keccak256(abi.encode(weight, new bytes32[](0), new uint32[](0)));
        // Trim to same length
        bytes32[] memory ids2 = new bytes32[](n);
        uint32[] memory bps2 = new uint32[](n);
        for (uint256 i; i < n; i++) {
            ids2[i] = ids[i];
            bps2[i] = bps[i];
        }
        if (n > 1) {
            _sortPairs(ids2, bps2);
        }
        return keccak256(abi.encode(weight, ids2, bps2));
    }

    function _sortPairs(bytes32[] memory ids, uint32[] memory bps) internal pure {
        // simple quicksort by id asc
        _qsort(ids, bps, int256(0), int256(ids.length - 1));
    }

    function _qsort(bytes32[] memory ids, uint32[] memory bps, int256 lo, int256 hi) private pure {
        int256 i = lo;
        int256 j = hi;
        bytes32 p = ids[uint256(lo + (hi - lo) / 2)];
        while (i <= j) {
            while (ids[uint256(i)] < p) i++;
            while (ids[uint256(j)] > p) j--;
            if (i <= j) {
                (ids[uint256(i)], ids[uint256(j)]) = (ids[uint256(j)], ids[uint256(i)]);
                (bps[uint256(i)], bps[uint256(j)]) = (bps[uint256(j)], bps[uint256(i)]);
                i++;
                j--;
            }
        }
        if (lo < j) _qsort(ids, bps, lo, j);
        if (i < hi) _qsort(ids, bps, i, hi);
    }

    function _qsortPairs(bytes32[] memory ids, uint32[] memory bps, int256 lo, int256 hi) private pure {
        int256 i = lo;
        int256 j = hi;
        bytes32 p = ids[uint256(lo + (hi - lo) / 2)];
        while (i <= j) {
            while (ids[uint256(i)] < p) i++;
            while (ids[uint256(j)] > p) j--;
            if (i <= j) {
                (ids[uint256(i)], ids[uint256(j)]) = (ids[uint256(j)], ids[uint256(i)]);
                (bps[uint256(i)], bps[uint256(j)]) = (bps[uint256(j)], bps[uint256(i)]);
                i++;
                j--;
            }
        }
        if (lo < j) _qsortPairs(ids, bps, lo, j);
        if (i < hi) _qsortPairs(ids, bps, i, hi);
    }
}
