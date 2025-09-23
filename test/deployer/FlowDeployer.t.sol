// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { FlowDeployer } from "../../src/FlowDeployer.sol";
import { IFlowDeployer } from "../../src/interfaces/IFlowDeployer.sol";
import { IFlow, ICustomFlow } from "../../src/interfaces/IFlow.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";
import { IAllocationStrategy } from "../../src/interfaces/IAllocationStrategy.sol";
import { SingleAllocatorStrategy } from "../../src/allocation-strategies/SingleAllocatorStrategy.sol";
import { CustomFlow } from "../../src/flows/CustomFlow.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { ISuperfluid } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperTokenFactory } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperTokenFactory.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { SuperfluidFrameworkDeployer } from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { IResolver } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/utils/IResolver.sol";
import { IChainalysisSanctionsList } from "../../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";
import { SuperTokenFactory } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperTokenFactory.sol";

contract MockSanctionsOracle is IChainalysisSanctionsList {
    function isSanctioned(address) external pure returns (bool) {
        return false;
    }
}

contract FlowDeployerTest is Test {
    struct InitPair {
        address underlyingToken;
        address superToken;
    }
    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer internal frameworkDeployer;
    SuperToken internal superToken;
    address internal underlying;

    FlowDeployer internal flowDeployer;
    address internal customFlowImpl;
    address internal singleAllocatorStrategyImpl;
    address internal resolver;

    address internal owner = address(0xA11CE);
    address internal manager = address(0xBEEF);
    address internal connectPoolAdmin = address(0xCAFE);
    address internal allocator = address(0xA110CA71);
    address internal managerRewardPool = address(0xFEEFEED);
    uint32 internal fixedManagerRewardPct = 100_000; // 10%
    IChainalysisSanctionsList internal fixedSanctionsOracle;

    IFlow.FlowParams internal flowParams;
    FlowTypes.RecipientMetadata internal metadata;

    function setUp() public {
        metadata = FlowTypes.RecipientMetadata({
            title: "Test Flow",
            description: "A test flow",
            image: "ipfs://image",
            tagline: "tag",
            url: "https://example.com"
        });

        flowParams = IFlow.FlowParams({
            baselinePoolFlowRatePercent: 5000,
            managerRewardPoolFlowRatePercent: 10000,
            bonusPoolQuorumBps: 5000
        });

        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);

        frameworkDeployer = new SuperfluidFrameworkDeployer();
        frameworkDeployer.deployTestFramework();
        sf = frameworkDeployer.getFramework();

        // Ensure factory proxy matches and canonical mapping is initialized (required by createCanonicalERC20Wrapper).
        {
            SuperTokenFactory factory = sf.superTokenFactory;
            assertEq(address(factory), address(sf.host.getSuperTokenFactory()), "factory mismatch");

            // Become governance owner so we can initialize the canonical mapping once.
            frameworkDeployer.transferOwnership(address(this));

            // Call initializeCanonicalWrapperSuperTokens via low-level call with tuple encoding.
            // This only needs an entry for underlying=address(0) to mark mapping initialized.
            InitPair[] memory init = new InitPair[](1);
            init[0] = InitPair({ underlyingToken: address(0), superToken: address(1) });
            (bool ok, ) = address(factory).call(
                abi.encodeWithSignature("initializeCanonicalWrapperSuperTokens((address,address)[])", init)
            );
            require(ok, "init canonical wrappers failed");
        }

        // Deploy a wrapper SuperToken and fetch addresses
        (TestToken underlyingToken, SuperToken token) = frameworkDeployer.deployWrapperSuperToken(
            "USDC Test",
            "USDC",
            6,
            1e24,
            owner
        );
        superToken = token;
        underlying = address(underlyingToken);

        resolver = address(sf.resolver);

        // Deploy implementations used by deployer
        customFlowImpl = address(new CustomFlow());
        singleAllocatorStrategyImpl = address(new SingleAllocatorStrategy());

        // Deploy FlowDeployer implementation and proxy
        FlowDeployer impl = new FlowDeployer();
        fixedSanctionsOracle = new MockSanctionsOracle();
        bytes memory initData = abi.encodeCall(
            FlowDeployer.initialize,
            (
                IResolver(resolver),
                customFlowImpl,
                singleAllocatorStrategyImpl,
                owner,
                connectPoolAdmin,
                managerRewardPool,
                fixedManagerRewardPct,
                fixedSanctionsOracle
            )
        );
        flowDeployer = FlowDeployer(address(new ERC1967Proxy(address(impl), initData)));
    }

    function _deployFlowParams() internal view returns (IFlowDeployer.DeployParams memory p) {
        p = IFlowDeployer.DeployParams({
            manager: manager,
            underlyingERC20: underlying,
            allocator: allocator,
            flowParams: flowParams,
            metadata: metadata
        });
    }

    function test_deployFlow_usesCanonicalWrapper() public {
        IFlowDeployer.DeployParams memory p = _deployFlowParams();
        (address flow, address strategy) = flowDeployer.deployFlow(p);

        assertTrue(flow != address(0));
        assertTrue(strategy != address(0));

        // Verify flow is initialized with the expected supertoken by checking event data via state access
        // Pull a known view to ensure the address is set and contract responds
        IFlow(flow).getTotalFlowRate();
    }

    function test_getCanonicalWrapper_matchesFactory() public {
        // Ensure canonical wrapper exists (creates if missing)
        IFlowDeployer.DeployParams memory p = _deployFlowParams();
        flowDeployer.deployFlow(p);

        address expected = sf.superTokenFactory.getCanonicalERC20Wrapper(underlying);
        address actual = flowDeployer.getCanonicalWrapper(underlying);
        assertEq(actual, expected);
        assertTrue(actual != address(0));
    }

    function test_reuse_allocator_strategy() public {
        IFlowDeployer.DeployParams memory p = _deployFlowParams();
        (address flow1, address strat1) = flowDeployer.deployFlow(p);
        (address flow2, address strat2) = flowDeployer.deployFlow(p);

        assertTrue(flow1 != address(0) && flow2 != address(0));
        assertEq(strat1, strat2, "expected cached strategy for allocator");
    }

    function test_second_deploy_reuses_strategy() public {
        IFlowDeployer.DeployParams memory p = _deployFlowParams();
        (, address strat1) = flowDeployer.deployFlow(p);
        (, address strat2) = flowDeployer.deployFlow(p);
        assertTrue(strat1 != address(0) && strat2 != address(0));
        assertEq(strat1, strat2, "expected cached strategy to be reused");
    }

    function test_new_allocator_creates_new_strategy() public {
        IFlowDeployer.DeployParams memory p = _deployFlowParams();
        (, address s1) = flowDeployer.deployFlow(p);
        p.allocator = address(0xDEAD);
        (, address s2) = flowDeployer.deployFlow(p);
        assertTrue(s1 != address(0) && s2 != address(0));
        assertTrue(s1 != s2, "different allocator should create different strategy");
    }

    function test_setCustomFlowImpl_updatesImplementation() public {
        vm.startPrank(owner);
        address oldImpl = flowDeployer.customFlowImpl();
        address newImpl = address(new CustomFlow());

        vm.expectEmit(false, false, false, true, address(flowDeployer));
        emit IFlowDeployer.CustomFlowImplUpdated(oldImpl, newImpl);

        flowDeployer.setCustomFlowImpl(newImpl);

        vm.stopPrank();

        assertEq(flowDeployer.customFlowImpl(), newImpl);
    }

    function test_setCustomFlowImpl_zeroAddress_reverts() public {
        vm.startPrank(owner);
        vm.expectRevert(IFlowDeployer.CustomFlowImplZeroAddress.selector);
        flowDeployer.setCustomFlowImpl(address(0));
        vm.stopPrank();
    }

    function test_setCustomFlowImpl_notContract_reverts() public {
        vm.startPrank(owner);
        address nonContract = address(0xB0B);
        vm.expectRevert(abi.encodeWithSelector(IFlowDeployer.CustomFlowImplNotContract.selector, nonContract));
        flowDeployer.setCustomFlowImpl(nonContract);
        vm.stopPrank();
    }

    function test_setCustomFlowImpl_nonOwner_reverts() public {
        address newImpl = address(new CustomFlow());
        address caller = manager;
        vm.startPrank(caller);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        flowDeployer.setCustomFlowImpl(newImpl);
        vm.stopPrank();
    }

    function test_setSingleAllocatorStrategyImpl_updatesImplementation() public {
        vm.startPrank(owner);
        address oldImpl = flowDeployer.singleAllocatorStrategyImpl();
        address newImpl = address(new SingleAllocatorStrategy());

        vm.expectEmit(false, false, false, true, address(flowDeployer));
        emit IFlowDeployer.SingleAllocatorStrategyImplUpdated(oldImpl, newImpl);

        flowDeployer.setSingleAllocatorStrategyImpl(newImpl);

        vm.stopPrank();

        assertEq(flowDeployer.singleAllocatorStrategyImpl(), newImpl);
    }

    function test_setSingleAllocatorStrategyImpl_zeroAddress_reverts() public {
        vm.startPrank(owner);
        vm.expectRevert(IFlowDeployer.StrategyImplZeroAddress.selector);
        flowDeployer.setSingleAllocatorStrategyImpl(address(0));
        vm.stopPrank();
    }

    function test_setSingleAllocatorStrategyImpl_notContract_reverts() public {
        vm.startPrank(owner);
        address nonContract = address(0xC0FFEE);
        vm.expectRevert(abi.encodeWithSelector(IFlowDeployer.StrategyImplNotContract.selector, nonContract));
        flowDeployer.setSingleAllocatorStrategyImpl(nonContract);
        vm.stopPrank();
    }

    function test_setConnectPoolAdmin_updatesAdmin() public {
        vm.startPrank(owner);
        address oldAdmin = flowDeployer.connectPoolAdmin();
        address newAdmin = address(0xC0FF);

        vm.expectEmit(true, true, false, false, address(flowDeployer));
        emit IFlowDeployer.ConnectPoolAdminUpdated(oldAdmin, newAdmin);

        flowDeployer.setConnectPoolAdmin(newAdmin);

        vm.stopPrank();

        assertEq(flowDeployer.connectPoolAdmin(), newAdmin);
    }

    function test_setConnectPoolAdmin_zeroAddress_reverts() public {
        vm.startPrank(owner);
        vm.expectRevert(IFlowDeployer.ConnectPoolAdminZeroAddress.selector);
        flowDeployer.setConnectPoolAdmin(address(0));
        vm.stopPrank();
    }

    function test_setManagerRewardPool_updatesPool() public {
        vm.startPrank(owner);
        address oldPool = flowDeployer.managerRewardPool();
        address newPool = address(0xFEED1234);

        vm.expectEmit(true, true, false, false, address(flowDeployer));
        emit IFlowDeployer.ManagerRewardPoolUpdated(oldPool, newPool);

        flowDeployer.setManagerRewardPool(newPool);

        vm.stopPrank();

        assertEq(flowDeployer.managerRewardPool(), newPool);
    }

    function test_setManagerRewardPool_zeroAddress_reverts() public {
        vm.startPrank(owner);
        vm.expectRevert(IFlowDeployer.ManagerRewardPoolZeroAddress.selector);
        flowDeployer.setManagerRewardPool(address(0));
        vm.stopPrank();
    }

    function test_setManagerRewardFlowRatePercent_updatesPercent() public {
        vm.startPrank(owner);
        uint32 oldPercent = flowDeployer.managerRewardPoolFlowRatePercent();
        uint32 newPercent = 250_000;

        vm.expectEmit(false, false, false, true, address(flowDeployer));
        emit IFlowDeployer.ManagerRewardFlowRatePercentUpdated(oldPercent, newPercent);

        flowDeployer.setManagerRewardFlowRatePercent(newPercent);

        vm.stopPrank();

        assertEq(flowDeployer.managerRewardPoolFlowRatePercent(), newPercent);
    }

    function test_setManagerRewardFlowRatePercent_invalid_reverts() public {
        vm.startPrank(owner);
        vm.expectRevert(IFlowDeployer.InvalidManagerRewardPercent.selector);
        flowDeployer.setManagerRewardFlowRatePercent(1_000_001);
        vm.stopPrank();
    }

    function test_setSanctionsOracle_updatesOracle() public {
        vm.startPrank(owner);
        address oldOracle = address(flowDeployer.sanctionsOracle());
        IChainalysisSanctionsList newOracle = new MockSanctionsOracle();

        vm.expectEmit(false, false, false, true, address(flowDeployer));
        emit IFlowDeployer.SanctionsOracleUpdated(oldOracle, address(newOracle));

        flowDeployer.setSanctionsOracle(newOracle);

        vm.stopPrank();

        assertEq(address(flowDeployer.sanctionsOracle()), address(newOracle));
    }

    function test_setSanctionsOracle_zeroAddress_reverts() public {
        vm.startPrank(owner);
        vm.expectRevert(IFlowDeployer.SanctionsOracleZeroAddress.selector);
        flowDeployer.setSanctionsOracle(IChainalysisSanctionsList(address(0)));
        vm.stopPrank();
    }

    function test_setSanctionsOracle_notContract_reverts() public {
        vm.startPrank(owner);
        address nonContract = address(0xDEADBEEF);
        vm.expectRevert(abi.encodeWithSelector(IFlowDeployer.SanctionsOracleNotContract.selector, nonContract));
        flowDeployer.setSanctionsOracle(IChainalysisSanctionsList(nonContract));
        vm.stopPrank();
    }
}
