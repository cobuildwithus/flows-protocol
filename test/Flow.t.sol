// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IFlow} from "../src/interfaces/IFlow.sol";
import {Flow} from "../src/Flow.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {PoolConfig} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {ERC1820RegistryCompiled} from
    "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import {SuperfluidFrameworkDeployer} from
    "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.sol";
import {TestToken} from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import {SuperToken} from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";

contract FlowTest is Test {
    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer internal deployer;
    SuperToken internal superToken;

    address flow;
    address flowImpl;
    address testUSDC;
    IFlow.FlowParams flowParams;

    address erc721Votes;

    address manager = address(0x1998);

    function deployFlow(address votingPowerAddress, address superTokenAddress) internal returns (address) {
        address flowProxy = address(new ERC1967Proxy(flowImpl, ""));

        vm.prank(address(manager));
        IFlow(flowProxy).initialize({
            nounsToken: votingPowerAddress,
            superToken: superTokenAddress,
            flowImpl: flowImpl,
            flowParams: flowParams
        });

        _transferTestTokenToFlow(flowProxy);

        return flowProxy;
    }

    function _transferTestTokenToFlow(address flowAddress) internal {
        uint256 amount = 1e6 * 10**18; 
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

    function setUp() public virtual {
        address votingPowerAddress = address(0x1);
        flowImpl = address(new Flow());

        flowParams = IFlow.FlowParams({
            tokenVoteWeight: 1e18, // Example token vote weight
            quorumVotesBPS: 5000, // Example quorum votes in basis points (50%)
            minVotingPowerToCreate: 100 * 1e18 // Minimum voting power required to create a grant
        });

        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);

        deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();
        (TestToken underlyingToken, SuperToken token) =
            deployer.deployWrapperSuperToken("MR Token", "MRx", 18, 1e18 * 1e9, manager);

        superToken = token;
        testUSDC = address(underlyingToken);

        flow = deployFlow(votingPowerAddress, address(superToken));
    }

}