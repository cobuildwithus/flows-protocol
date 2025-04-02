// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import { IFlow, INounsFlow } from "../../src/interfaces/IFlow.sol";
import { NounsFlow } from "../../src/NounsFlow.sol";
import { TokenVerifier } from "../../src/state-proof/TokenVerifier.sol";
import { IStateProof } from "../../src/interfaces/IStateProof.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { PoolConfig } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { SuperfluidFrameworkDeployer } from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { FlowTypes } from "../../src/storage/FlowStorageV1.sol";
import { RewardPool } from "../../src/RewardPool.sol";
import { IRewardPool } from "../../src/interfaces/IRewardPool.sol";
import { IChainalysisSanctionsList } from "../../src/interfaces/external/chainalysis/IChainalysisSanctionsList.sol";

contract NounsFlowTest is Test {
    using stdJson for string;

    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer internal deployer;
    SuperToken internal superToken;

    NounsFlow flow;
    address flowImpl;
    address testUSDC;
    IFlow.FlowParams flowParams;

    TokenVerifier verifier;
    IRewardPool rewardPool;
    address manager = address(0x1998);

    FlowTypes.RecipientMetadata flowMetadata;
    FlowTypes.RecipientMetadata recipientMetadata;

    address NOUNS_TOKEN_ADDRESS = 0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03;

    function deployFlow(address verifierAddress, address superTokenAddress) internal returns (NounsFlow) {
        address flowProxy = address(new ERC1967Proxy(flowImpl, ""));
        rewardPool = deployRewardPool(superTokenAddress, flowProxy, address(manager));

        vm.prank(address(manager));
        INounsFlow(flowProxy).initialize({
            initialOwner: address(manager),
            verifier: verifierAddress,
            superToken: superTokenAddress,
            flowImpl: flowImpl,
            manager: manager,
            managerRewardPool: address(rewardPool),
            parent: address(0),
            flowParams: flowParams,
            metadata: flowMetadata,
            sanctionsOracle: IChainalysisSanctionsList(address(0))
        });

        _transferTestTokenToFlow(flowProxy, 10_000 * 10 ** 18); //10k usdc a month to start

        // so we have nouns available
        // in the total vote weight supply function
        vm.warp(1628399590);

        // set small flow rate
        vm.prank(manager);
        IFlow(flowProxy).setFlowRate(385 * 10 ** 13); // 0.00385 tokens per second

        return NounsFlow(flowProxy);
    }

    function deployRewardPool(
        address superTokenAddress,
        address flowAddress,
        address initialOwner
    ) internal returns (IRewardPool) {
        // Deploy the implementation contract
        address rewardPoolImpl = address(new RewardPool());

        // Deploy the proxy contract
        address rewardPoolProxy = address(new ERC1967Proxy(rewardPoolImpl, ""));

        // Initialize the proxy
        IRewardPool(rewardPoolProxy).initialize(ISuperToken(superTokenAddress), manager, flowAddress, initialOwner);

        return IRewardPool(rewardPoolProxy);
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

    function _setUpWithForkBlock(uint256 blockNumber) public virtual {
        _setUp();
        vm.createSelectFork(vm.rpcUrl("base"), blockNumber);
    }

    function _setUp() public virtual {
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

        verifier = new TokenVerifier(NOUNS_TOKEN_ADDRESS);
        flowImpl = address(new NounsFlow());

        flowParams = IFlow.FlowParams({
            tokenVoteWeight: 1e18 * 1000, // Example token vote weight
            baselinePoolFlowRatePercent: 5000, // 1000 BPS
            managerRewardPoolFlowRatePercent: 1000 // 1000 BPS
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

        flow = deployFlow(address(verifier), address(superToken));
    }

    function _setupBaseParameters() internal view returns (IStateProof.BaseParameters memory) {
        string memory rootPath = vm.projectRoot();
        string memory proofPath = string.concat(rootPath, "/test/proof-data/papercliplabs.json");
        string memory json = vm.readFile(proofPath);

        return
            IStateProof.BaseParameters({
                beaconRoot: json.readBytes32(".beaconRoot"),
                beaconOracleTimestamp: uint256(json.readBytes32(".beaconOracleTimestamp")),
                executionStateRoot: json.readBytes32(".executionStateRoot"),
                stateRootProof: abi.decode(json.parseRaw(".stateRootProof"), (bytes32[])),
                accountProof: abi.decode(json.parseRaw(".accountProof"), (bytes[]))
            });
    }

    function _setupStorageProofs() internal view returns (bytes[][][] memory, bytes[][] memory) {
        string memory rootPath = vm.projectRoot();
        string memory proofPath = string.concat(rootPath, "/test/proof-data/papercliplabs.json");
        string memory json = vm.readFile(proofPath);

        bytes[][][] memory ownershipStorageProofs = new bytes[][][](1);
        ownershipStorageProofs[0] = new bytes[][](2);
        ownershipStorageProofs[0][0] = abi.decode(json.parseRaw(".ownershipStorageProof1"), (bytes[]));
        ownershipStorageProofs[0][1] = abi.decode(json.parseRaw(".ownershipStorageProof2"), (bytes[]));

        bytes[][] memory delegateStorageProofs = abi.decode(json.parseRaw(".delegateStorageProofs"), (bytes[][]));

        return (ownershipStorageProofs, delegateStorageProofs);
    }

    function getStateProofParams(string memory path) internal view returns (IStateProof.Parameters memory) {
        string memory json = vm.readFile(path);
        return
            IStateProof.Parameters({
                beaconRoot: json.readBytes32(".beaconRoot"),
                beaconOracleTimestamp: uint256(json.readBytes32(".beaconOracleTimestamp")),
                executionStateRoot: json.readBytes32(".executionStateRoot"),
                stateRootProof: abi.decode(json.parseRaw(".stateRootProof"), (bytes32[])),
                storageProof: abi.decode(json.parseRaw(".storageProof"), (bytes[])),
                accountProof: abi.decode(json.parseRaw(".accountProof"), (bytes[]))
            });
    }
}
