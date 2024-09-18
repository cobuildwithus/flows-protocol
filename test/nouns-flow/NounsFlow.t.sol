// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

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
import { FlowStorageV1 } from "../../src/storage/FlowStorageV1.sol";

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

    address manager = address(0x1998);

    FlowStorageV1.RecipientMetadata flowMetadata;
    FlowStorageV1.RecipientMetadata recipientMetadata;

    address NOUNS_TOKEN_ADDRESS = 0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03;

    function deployFlow(address verifierAddress, address superTokenAddress) internal returns (NounsFlow) {
        address flowProxy = address(new ERC1967Proxy(flowImpl, ""));

        vm.prank(address(manager));
        INounsFlow(flowProxy).initialize({
            initialOwner: address(manager),
            verifier: verifierAddress,
            superToken: superTokenAddress,
            flowImpl: flowImpl,
            manager: manager,
            parent: address(0),
            flowParams: flowParams,
            metadata: flowMetadata
        });

        _transferTestTokenToFlow(flowProxy, 10_000 * 10 ** 18); //10k usdc a month to start

        // set small flow rate
        vm.prank(manager);
        IFlow(flowProxy).setFlowRate(385 * 10 ** 13); // 0.00385 tokens per second

        return NounsFlow(flowProxy);
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
        vm.createSelectFork("https://mainnet.base.org", blockNumber);
        flowMetadata = FlowStorageV1.RecipientMetadata({
            title: "Test Flow",
            description: "A test flow",
            image: "ipfs://image",
            tagline: "Test Flow Tagline",
            url: "https://testflow.com"
        });

        recipientMetadata = FlowStorageV1.RecipientMetadata({
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
            baselinePoolFlowRatePercent: 1000 // 1000 BPS
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
