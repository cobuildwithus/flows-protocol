// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { SingleAllocatorStrategy } from "../../../src/allocation-strategies/SingleAllocatorStrategy.sol";
import { CustomFlow } from "../../../src/flows/CustomFlow.sol";
import { IFlow, ICustomFlow } from "../../../src/interfaces/IFlow.sol";
import { FlowTypes } from "../../../src/storage/FlowStorage.sol";
import { RewardPool } from "../../../src/token-issuance/RewardPool.sol";
import { IRewardPool } from "../../../src/interfaces/IRewardPool.sol";
import { IAllocationStrategy } from "../../../src/interfaces/IAllocationStrategy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Superfluid helpers
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperfluidFrameworkDeployer } from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";

import { IChainalysisSanctionsList } from "../../../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";

contract SingleAllocatorFlowTestBase is Test {
    // ────────────── Addresses ──────────────
    address internal constant _manager = address(0x1998);
    address internal constant _allocator = address(0xA11C08);
    address internal constant _attacker = address(0xBAD);
    address internal constant _newAllocator = address(0xC0FFEE);

    // ────────────── Superfluid helpers ──────────────
    SuperfluidFrameworkDeployer internal _deployer;
    SuperfluidFrameworkDeployer.Framework internal _sf;
    SuperToken internal _superToken;
    address internal _underlyingToken;

    // ────────────── Core contracts ──────────────
    SingleAllocatorStrategy internal _strategyImpl;
    address internal _strategyProxy;

    CustomFlow internal _flow;
    address internal _flowImpl;

    RewardPool internal _managerRewardPool;

    // ────────────── Helpers ──────────────
    FlowTypes.RecipientMetadata internal _flowMetadata;
    FlowTypes.RecipientMetadata internal _recipientMetadata;

    IFlow.FlowParams internal _flowParams;

    // Constants
    uint256 internal constant _INITIAL_BALANCE = 10_000 * 1e18;

    // ────────────────────────────────────────────────
    //                     Setup
    // ────────────────────────────────────────────────

    function setUp() public {
        // metadata setup
        _flowMetadata = FlowTypes.RecipientMetadata({
            title: "Test Flow",
            description: "Single allocator flow",
            image: "ipfs://image",
            tagline: "SingleAllocator",
            url: "https://test.flow"
        });

        _recipientMetadata = FlowTypes.RecipientMetadata({
            title: "Recipient",
            description: "Some recipient",
            image: "ipfs://image",
            tagline: "Recipient",
            url: "https://recipient"
        });

        // Deploy Superfluid test framework (required by Flow)
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
        _deployer = new SuperfluidFrameworkDeployer();
        _deployer.deployTestFramework();
        _sf = _deployer.getFramework();
        // token wrapper
        (TestToken underlying, SuperToken superToken) = _deployer.deployWrapperSuperToken(
            "MockUSD",
            "mUSDx",
            18,
            type(uint256).max,
            _manager
        );
        _superToken = superToken;
        _underlyingToken = address(underlying);

        // Deploy strategy implementation & proxy
        _strategyImpl = new SingleAllocatorStrategy();
        _strategyProxy = address(new ERC1967Proxy(address(_strategyImpl), ""));

        // Initialize strategy (owner is manager)
        vm.prank(_manager);
        SingleAllocatorStrategy(_strategyProxy).initialize(_manager, _allocator);

        // Deploy Flow implementation
        _flowImpl = address(new CustomFlow());

        // Deploy Flow proxy
        address flowProxy = address(new ERC1967Proxy(_flowImpl, ""));

        // Manager reward pool (proxy)
        _managerRewardPool = _deployRewardPool(address(_superToken), _manager, flowProxy, _manager);

        // Setup flow params
        _flowParams = IFlow.FlowParams({
            baselinePoolFlowRatePercent: 5_000, // 0.5%
            managerRewardPoolFlowRatePercent: 100_000, // 10%
            bonusPoolQuorumBps: 50_000 // 5%
        });

        // Initialize Flow proxy
        IAllocationStrategy[] memory strategies = new IAllocationStrategy[](1);
        strategies[0] = IAllocationStrategy(_strategyProxy);

        vm.prank(_manager);
        ICustomFlow(flowProxy).initialize({
            initialOwner: _manager,
            superToken: address(_superToken),
            flowImpl: _flowImpl,
            manager: _manager,
            managerRewardPool: address(_managerRewardPool),
            parent: address(0),
            connectPoolAdmin: address(0),
            flowParams: _flowParams,
            metadata: _flowMetadata,
            sanctionsOracle: IChainalysisSanctionsList(address(0)),
            strategies: strategies
        });

        _flow = CustomFlow(flowProxy);

        // fund flow with tokens
        _fundFlow(flowProxy, _INITIAL_BALANCE);

        // minimal flow rate
        vm.prank(_manager);
        _flow.setFlowRate(int96(uint96(385 * 10 ** 13))); // ~0.00385 tokens/s
    }

    // ────────────────────────────────────────────────
    //                     Helpers
    // ────────────────────────────────────────────────

    function _deployRewardPool(
        address superTokenAddress,
        address poolManager,
        address flowAddress,
        address initialOwner
    ) internal returns (RewardPool) {
        address rewardImpl = address(new RewardPool());
        address proxy = address(new ERC1967Proxy(rewardImpl, ""));

        IRewardPool(proxy).initialize(ISuperToken(superTokenAddress), poolManager, flowAddress, initialOwner);
        return RewardPool(proxy);
    }

    function _fundFlow(address flowAddress, uint256 amount) internal {
        vm.startPrank(_manager);
        // mint underlying
        TestToken(_underlyingToken).mint(_manager, amount);
        // approve and upgrade
        TestToken(_underlyingToken).approve(address(_superToken), amount);
        _superToken.upgrade(amount);
        // transfer to flow contract
        _superToken.transfer(flowAddress, amount);
        vm.stopPrank();
    }

    function _addRecipient(bytes32 rid, address recipientAddr) internal {
        vm.prank(_manager);
        _flow.addRecipient(rid, recipientAddr, _recipientMetadata);
    }

    // Helper to build allocationData[][] with one empty inner bytes[]
    function _defaultAllocationData() internal pure returns (bytes[][] memory arr) {
        arr = new bytes[][](1);
        arr[0] = new bytes[](1);
        arr[0][0] = bytes("");
    }

    // =========================
    // Witness caching for tests
    // =========================

    struct PrevWitnessCacheItem {
        bool exists;
        uint256 prevWeight;
        bytes32[] recipientIds;
        uint32[] bps;
    }

    // strategy => allocationKey => cached previous allocation witness
    mapping(address => mapping(uint256 => PrevWitnessCacheItem)) internal _prevWitness;

    function _encodePrevWitness(address strategyAddr, uint256 allocationKey) internal view returns (bytes memory) {
        PrevWitnessCacheItem storage item = _prevWitness[strategyAddr][allocationKey];
        if (!item.exists) return "";
        return abi.encode(item.prevWeight, item.recipientIds, item.bps);
    }

    function _buildWitnesses(
        address allocator,
        bytes[][] memory allocationData
    ) internal view returns (bytes[][] memory) {
        bytes[][] memory witnesses = new bytes[][](allocationData.length);
        for (uint256 i = 0; i < allocationData.length; i++) {
            witnesses[i] = new bytes[](allocationData[i].length);
            for (uint256 j = 0; j < allocationData[i].length; j++) {
                uint256 key = IAllocationStrategy(_strategyProxy).allocationKey(allocator, allocationData[i][j]);
                witnesses[i][j] = _encodePrevWitness(_strategyProxy, key);
            }
        }
        return witnesses;
    }

    function _buildEmptyWitnesses(bytes[][] memory allocationData) internal pure returns (bytes[][] memory) {
        bytes[][] memory witnesses = new bytes[][](allocationData.length);
        for (uint256 i = 0; i < allocationData.length; i++) {
            witnesses[i] = new bytes[](allocationData[i].length);
            for (uint256 j = 0; j < allocationData[i].length; j++) {
                witnesses[i][j] = "";
            }
        }
        return witnesses;
    }

    function _updateWitnessCache(
        address allocator,
        bytes[][] memory allocationData,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations
    ) internal {
        address strategyAddr = _strategyProxy;
        for (uint256 i = 0; i < allocationData.length; i++) {
            for (uint256 j = 0; j < allocationData[i].length; j++) {
                uint256 key = IAllocationStrategy(strategyAddr).allocationKey(allocator, allocationData[i][j]);
                uint256 weightUsed = IAllocationStrategy(strategyAddr).currentWeight(key);

                PrevWitnessCacheItem storage item = _prevWitness[strategyAddr][key];
                item.exists = true;
                item.prevWeight = weightUsed;
                item.recipientIds = recipientIds;
                item.bps = percentAllocations;
            }
        }
    }

    function allocateWithWitnessHelper(
        address allocator,
        bytes[][] memory allocationData,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations
    ) internal {
        bytes[][] memory witnesses = _buildWitnesses(allocator, allocationData);
        vm.prank(allocator);
        _flow.allocateWithWitness(allocationData, witnesses, recipientIds, percentAllocations);
        _updateWitnessCache(allocator, allocationData, recipientIds, percentAllocations);
    }

    function allocateWithWitnessHelper(
        address allocator,
        bytes[][] memory allocationData,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations,
        bytes memory expectedRevert
    ) internal {
        bytes[][] memory witnesses = allocationData.length == 0
            ? _buildEmptyWitnesses(allocationData)
            : _buildWitnesses(allocator, allocationData);
        if (expectedRevert.length > 0) vm.expectRevert(expectedRevert);
        vm.prank(allocator);
        _flow.allocateWithWitness(allocationData, witnesses, recipientIds, percentAllocations);
        _updateWitnessCache(allocator, allocationData, recipientIds, percentAllocations);
    }
}
