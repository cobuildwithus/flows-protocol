// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { IFlow, IRevolutionFlow } from "../../src/interfaces/IFlow.sol";
import { RevolutionFlow } from "../../src/flows/RevolutionFlow.sol";
import { MockERC721 } from "../mocks/MockERC721.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { ISuperfluid, ISuperToken, ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { SuperfluidFrameworkDeployer } from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";
import { RewardPool } from "../../src/token-issuance/RewardPool.sol";
import { IRewardPool } from "../../src/interfaces/IRewardPool.sol";
import { BulkPoolWithdraw } from "../../src/macros/BulkPoolWithdraw.sol";
import { IChainalysisSanctionsList } from "../../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";

contract RevolutionFlowTest is Test {
    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer internal deployer;
    SuperToken internal superToken;
    RewardPool internal dummyRewardPool;

    RevolutionFlow flow;
    address flowImpl;
    address testUSDC;
    IFlow.FlowParams flowParams;

    MockERC721 nounsToken;
    ERC20 erc20Token;

    address manager = address(0x1998);

    FlowTypes.RecipientMetadata flowMetadata;
    FlowTypes.RecipientMetadata recipientMetadata;

    function deployFlow(address erc721, address superTokenAddress) internal returns (RevolutionFlow) {
        address flowProxy = address(new ERC1967Proxy(flowImpl, ""));
        dummyRewardPool = deployRewardPool(superTokenAddress, manager, address(flowProxy), address(manager));

        vm.prank(address(manager));
        IRevolutionFlow(flowProxy).initialize({
            initialOwner: address(manager),
            superToken: superTokenAddress,
            flowImpl: flowImpl,
            manager: manager,
            managerRewardPool: address(dummyRewardPool),
            parent: address(0),
            flowParams: flowParams,
            metadata: flowMetadata,
            sanctionsOracle: IChainalysisSanctionsList(address(0)),
            data: abi.encode(flowImpl, erc721, address(erc20Token), 1e18)
        });

        _transferTestTokenToFlow(flowProxy, 10_000 * 10 ** 18); //10k usdc a month to start

        // set small flow rate
        vm.prank(manager);
        IFlow(flowProxy).setFlowRate(385 * 10 ** 13); // 0.00385 tokens per second

        return RevolutionFlow(flowProxy);
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
        flowImpl = address(new RevolutionFlow());
        erc20Token = new ERC20("Test Token", "TEST");

        flowParams = IFlow.FlowParams({
            tokenVoteWeight: 1e18 * 1000, // Example token vote weight
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

        flow = deployFlow(address(nounsToken), address(superToken));
    }
}
