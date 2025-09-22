// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { IFlow, ICustomFlow } from "../../src/interfaces/IFlow.sol";
import { CustomFlow } from "../../src/flows/CustomFlow.sol";
import { ERC721VotesStrategy } from "../../src/allocation-strategies/ERC721VotesStrategy.sol";
import { MockERC721 } from "../mocks/MockERC721.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";
import { RewardPool } from "../../src/token-issuance/RewardPool.sol";
import { IRewardPool } from "../../src/interfaces/IRewardPool.sol";
import { IAllocationStrategy } from "../../src/interfaces/IAllocationStrategy.sol";
import { IERC721Votes } from "../../src/interfaces/IERC721Votes.sol";
import { IChainalysisSanctionsList } from "../../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";
import { WitnessCacheHelper } from "../helpers/WitnessCacheHelper.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ISuperfluid, ISuperToken, ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { SuperfluidFrameworkDeployer } from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";

contract ERC721FlowTest is Test, WitnessCacheHelper {
    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer internal deployer;
    SuperToken internal superToken;
    RewardPool internal dummyRewardPool;

    CustomFlow flow;
    address flowImpl;
    address testUSDC;
    IFlow.FlowParams flowParams;

    address votingStrategyImpl;
    address votingStrategyProxy;
    IAllocationStrategy[] strategies;

    MockERC721 nounsToken;

    address manager = address(0x1998);

    FlowTypes.RecipientMetadata flowMetadata;
    FlowTypes.RecipientMetadata recipientMetadata;

    function deployFlow(address erc721, address superTokenAddress) internal returns (CustomFlow) {
        address flowProxy = address(new ERC1967Proxy(flowImpl, ""));
        dummyRewardPool = deployRewardPool(superTokenAddress, manager, address(flowProxy), address(manager));

        vm.prank(address(manager));
        ICustomFlow(flowProxy).initialize({
            initialOwner: address(manager),
            superToken: superTokenAddress,
            flowImpl: flowImpl,
            manager: manager,
            managerRewardPool: address(dummyRewardPool),
            parent: address(0),
            connectPoolAdmin: address(0),
            flowParams: flowParams,
            metadata: flowMetadata,
            sanctionsOracle: IChainalysisSanctionsList(address(0)),
            strategies: strategies
        });

        _transferTestTokenToFlow(flowProxy, 10_000 * 10 ** 18); //10k usdc a month to start

        // set small flow rate
        vm.prank(manager);
        IFlow(flowProxy).setFlowRate(385 * 10 ** 13); // 0.00385 tokens per second

        return CustomFlow(flowProxy);
    }

    function _transferTestTokenToFlow(address flowAddress, uint256 amount) internal {
        vm.startPrank(manager);

        // Mint underlying tokens
        TestToken(testUSDC).mint(manager, amount);

        // Approve SuperToken to spend underlying tokens
        TestToken(testUSDC).approve(address(superToken), amount);

        // Upgrade (wrap) the tokens
        ISuperToken(address(superToken)).upgrade(amount);

        // Transfer the wrapped tokens to the Flow contract
        ISuperToken(address(superToken)).transfer(flowAddress, amount);

        vm.stopPrank();
    }

    function _prepTokens(uint256[] memory tokenIds) internal pure returns (bytes[][] memory) {
        bytes[][] memory allocationData = new bytes[][](1);
        allocationData[0] = new bytes[](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            allocationData[0][i] = abi.encode(tokenIds[i]);
        }

        return allocationData;
    }

    function allocateWithWitnessHelper(
        address allocator,
        bytes[][] memory allocationData,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations
    ) internal {
        _allocateWithWitnessForStrategies(
            allocator,
            allocationData,
            strategies,
            address(flow),
            recipientIds,
            percentAllocations
        );
    }

    function allocateWithWitnessHelper(
        address allocator,
        bytes[][] memory allocationData,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations,
        bytes memory expectedRevert
    ) internal {
        _allocateWithWitnessForStrategiesExpectRevert(
            allocator,
            allocationData,
            strategies,
            address(flow),
            recipientIds,
            percentAllocations,
            expectedRevert
        );
    }

    function allocateTokensWithWitnessHelper(
        address allocator,
        uint256[] memory tokenIds,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations
    ) internal {
        bytes[][] memory allocationData = _prepTokens(tokenIds);
        bytes[][] memory witnesses = _buildWitnessesForStrategies(allocator, allocationData, strategies);
        _sortAllocPairs(recipientIds, percentAllocations);
        vm.prank(allocator);
        flow.allocate(allocationData, witnesses, recipientIds, percentAllocations);
        _updateWitnessCacheForStrategies(allocator, allocationData, strategies, recipientIds, percentAllocations);
    }

    function allocateTokensWithWitnessHelper(
        address allocator,
        uint256[] memory tokenIds,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations,
        bytes memory expectedRevert
    ) internal {
        bytes[][] memory allocationData = _prepTokens(tokenIds);
        bytes[][] memory witnesses = _buildWitnessesForStrategies(allocator, allocationData, strategies);
        _sortAllocPairs(recipientIds, percentAllocations);
        if (expectedRevert.length > 0) vm.expectRevert(expectedRevert);
        vm.prank(allocator);
        flow.allocate(allocationData, witnesses, recipientIds, percentAllocations);
        _updateWitnessCacheForStrategies(allocator, allocationData, strategies, recipientIds, percentAllocations);
    }

    function tokenVoteWeight() internal view returns (uint256) {
        return ERC721VotesStrategy(votingStrategyProxy).tokenVoteWeight();
    }

    function deployRewardPool(
        address superTokenAddress,
        address poolManager,
        address flowAddress,
        address initialOwner
    ) internal returns (RewardPool) {
        // Deploy the implementation contract
        address rewardPoolImpl = address(new RewardPool());

        // Deploy the proxy contract
        address rewardPoolProxy = address(new ERC1967Proxy(rewardPoolImpl, ""));

        // Initialize the proxy
        IRewardPool(rewardPoolProxy).initialize(ISuperToken(superTokenAddress), poolManager, flowAddress, initialOwner);

        return RewardPool(rewardPoolProxy);
    }

    function deployMock721(string memory name, string memory symbol) public virtual returns (MockERC721) {
        return new MockERC721(name, symbol);
    }

    function setUp() public virtual {
        flowMetadata = FlowTypes.RecipientMetadata({
            title: "Test Flow",
            description: "A test flow",
            image: "ipfs://image",
            tagline: "Test Flow Tagline",
            url: "https://testflow.com"
        });

        recipientMetadata = FlowTypes.RecipientMetadata({
            title: "Test Recipient",
            description: "A test recipient",
            image: "ipfs://image",
            tagline: "Test Recipient Tagline",
            url: "https://testrecipient.com"
        });

        nounsToken = deployMock721("Nouns", "NOUN");
        flowImpl = address(new CustomFlow());

        flowParams = IFlow.FlowParams({
            baselinePoolFlowRatePercent: 5000, // 1000 BPS
            managerRewardPoolFlowRatePercent: 1e6 / 10, // 10%
            bonusPoolQuorumBps: 1e6 / 20 // 5%
        });

        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);

        deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();
        (TestToken underlyingToken, SuperToken token) = deployer.deployWrapperSuperToken(
            "MR Token",
            "MRx",
            18,
            1e18 * 1e9,
            manager
        );

        superToken = token;
        testUSDC = address(underlyingToken);

        votingStrategyImpl = address(new ERC721VotesStrategy());
        votingStrategyProxy = address(new ERC1967Proxy(votingStrategyImpl, ""));
        ERC721VotesStrategy(votingStrategyProxy).initialize(manager, IERC721Votes(address(nounsToken)), 1e18 * 1000);
        strategies = new IAllocationStrategy[](1);
        strategies[0] = IAllocationStrategy(votingStrategyProxy);

        flow = deployFlow(address(nounsToken), address(superToken));
    }
}
