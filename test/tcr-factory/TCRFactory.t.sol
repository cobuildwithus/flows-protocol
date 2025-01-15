// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { TCRFactory } from "../../src/tcr/TCRFactory.sol";
import { FlowTCR } from "../../src/tcr/FlowTCR.sol";
import { ERC20VotesMintable } from "../../src/ERC20VotesMintable.sol";
import { ERC20VotesArbitrator } from "../../src/tcr/ERC20VotesArbitrator.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC721Flow } from "../../src/ERC721Flow.sol";
import { ITCRFactory } from "../../src/tcr/interfaces/ITCRFactory.sol";
import { IManagedFlow } from "../../src/interfaces/IManagedFlow.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IArbitrator } from "../../src/tcr/interfaces/IArbitrator.sol";
import { FlowTypes } from "../../src/storage/FlowStorageV1.sol";
import { TokenEmitter } from "../../src/TokenEmitter.sol";
import { ProtocolRewards } from "../../src/protocol-rewards/ProtocolRewards.sol";
import { RewardPool } from "../../src/RewardPool.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { PoolConfig } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { SuperfluidFrameworkDeployer } from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";

contract TCRFactoryTest is Test {
    // Contracts
    TCRFactory public tcrFactory;
    FlowTCR public flowTCRImpl;
    ERC20VotesMintable public erc20Impl;
    ERC20VotesArbitrator public arbitratorImpl;
    RewardPool public rewardPoolImpl;
    TokenEmitter public tokenEmitterImpl;
    ProtocolRewards public protocolRewardsImpl;

    // Addresses
    address public owner;
    address public founderRewardAddress;
    address public governor;
    address public flowContract;
    address public protocolFeeRecipient;
    address public WETH;
    // Test Parameters
    uint256 public constant SUBMISSION_BASE_DEPOSIT = 100 ether;
    uint256 public constant REMOVAL_BASE_DEPOSIT = 100 ether;
    uint256 public constant SUBMISSION_CHALLENGE_BASE_DEPOSIT = 100 ether;
    uint256 public constant REMOVAL_CHALLENGE_BASE_DEPOSIT = 100 ether;
    uint256 public constant CHALLENGE_PERIOD = 3 days;
    uint256 public constant STAKE_MULTIPLIER = 10000; // 100%
    uint256 public constant FOUNDER_REWARD_DURATION = 5 * (365 days);

    // Arbitrator Parameters
    uint256 public constant VOTING_PERIOD = 86_400;
    uint256 public constant VOTING_DELAY = 1;
    uint256 public constant REVEAL_PERIOD = 86_400;
    uint256 public constant ARBITRATION_COST = 1e18 / 10_000;

    // Superfluid
    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer internal deployer;
    SuperToken internal superToken;
    address testUSDC;

    function setUp() public {
        owner = address(this);
        governor = makeAddr("governor");
        flowContract = address(new ERC1967Proxy(address(new ERC721Flow()), ""));
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        WETH = makeAddr("WETH");
        founderRewardAddress = makeAddr("founderRewardAddress");

        // Deploy implementation contracts
        protocolRewardsImpl = new ProtocolRewards();
        flowTCRImpl = new FlowTCR();
        erc20Impl = new ERC20VotesMintable();
        arbitratorImpl = new ERC20VotesArbitrator();
        rewardPoolImpl = new RewardPool();
        tokenEmitterImpl = new TokenEmitter(address(protocolRewardsImpl), protocolFeeRecipient);

        // Deploy TCRFactory
        TCRFactory tcrFactoryImpl = new TCRFactory();
        ERC1967Proxy proxy = new ERC1967Proxy(address(tcrFactoryImpl), "");
        tcrFactory = TCRFactory(address(proxy));

        // Initialize TCRFactory
        ITCRFactory(address(tcrFactory)).initialize({
            initialOwner: owner,
            flowTCRImplementation: address(flowTCRImpl),
            arbitratorImplementation: address(arbitratorImpl),
            erc20Implementation: address(erc20Impl),
            rewardPoolImplementation: address(rewardPoolImpl),
            tokenEmitterImplementation: address(tokenEmitterImpl),
            weth: WETH
        });

        // Setup Superfluid
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);

        deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();
        (TestToken underlyingToken, SuperToken token) = deployer.deployWrapperSuperToken(
            "MR Token",
            "MRx",
            18,
            1e18 * 1e9,
            owner
        );

        superToken = token;
        testUSDC = address(underlyingToken);
    }

    function testDeployFlowTCR() public {
        // Prepare parameters
        ITCRFactory.FlowTCRParams memory flowParams = ITCRFactory.FlowTCRParams({
            flowContract: IManagedFlow(flowContract),
            arbitratorExtraData: "",
            registrationMetaEvidence: "ipfs://registration",
            clearingMetaEvidence: "ipfs://clearing",
            governor: governor,
            submissionBaseDeposit: SUBMISSION_BASE_DEPOSIT,
            removalBaseDeposit: REMOVAL_BASE_DEPOSIT,
            submissionChallengeBaseDeposit: SUBMISSION_CHALLENGE_BASE_DEPOSIT,
            removalChallengeBaseDeposit: REMOVAL_CHALLENGE_BASE_DEPOSIT,
            challengePeriodDuration: CHALLENGE_PERIOD,
            requiredRecipientType: FlowTypes.RecipientType.None
        });

        ITCRFactory.ArbitratorParams memory arbitratorParams = ITCRFactory.ArbitratorParams({
            votingPeriod: VOTING_PERIOD,
            votingDelay: VOTING_DELAY,
            revealPeriod: REVEAL_PERIOD,
            arbitrationCost: ARBITRATION_COST
        });

        ITCRFactory.ERC20Params memory erc20Params = ITCRFactory.ERC20Params({
            initialOwner: governor,
            name: "Test Token",
            symbol: "TST"
        });

        ITCRFactory.RewardPoolParams memory rewardPoolParams = ITCRFactory.RewardPoolParams({
            superToken: ISuperToken(address(superToken))
        });

        ITCRFactory.TokenEmitterParams memory tokenEmitterParams = ITCRFactory.TokenEmitterParams({
            curveSteepness: int256(1e18) / 100,
            basePrice: int256(1e18) / 3000,
            maxPriceIncrease: int256(1e18) / 300,
            supplyOffset: int256(1e18) * 1000,
            priceDecayPercent: int256(1e18) / 4, // 25%
            perTimeUnit: int256(1e18) * 500, // 500 tokens per day
            founderRewardAddress: founderRewardAddress,
            founderRewardDuration: FOUNDER_REWARD_DURATION
        });

        // Deploy FlowTCR ecosystem
        ITCRFactory.DeployedContracts memory deployedContracts = tcrFactory.deployFlowTCR(
            flowParams,
            arbitratorParams,
            erc20Params,
            rewardPoolParams,
            tokenEmitterParams
        );

        // Verify deployment
        assertTrue(deployedContracts.tcrAddress != address(0), "FlowTCR not deployed");

        // Check if RewardPool is properly initialized
        RewardPool rewardPool = RewardPool(deployedContracts.rewardPoolAddress);
        assertEq(address(rewardPool.superToken()), address(superToken), "SuperToken not set correctly in RewardPool");

        // Verify the Superfluid pool was created
        assertTrue(address(rewardPool.rewardPool()) != address(0), "Superfluid pool not created in RewardPool");

        // Check if the Superfluid pool is using the correct SuperToken
        ISuperfluidPool superfluidPool = rewardPool.rewardPool();
        assertEq(address(superfluidPool.superToken()), address(superToken), "Incorrect SuperToken in Superfluid pool");

        // Check if ERC20VotesMintable is properly initialized
        ERC20VotesMintable erc20 = ERC20VotesMintable(deployedContracts.erc20Address);
        assertEq(erc20.name(), "Test Token", "ERC20 name not set correctly");
        assertEq(erc20.symbol(), "TST", "ERC20 symbol not set correctly");
        assertEq(erc20.decimals(), 18, "ERC20 decimals not set correctly");
        assertEq(erc20.owner(), governor, "ERC20 owner not set correctly");
        assertEq(erc20.minter(), deployedContracts.tokenEmitterAddress, "ERC20 minter not set correctly");
        assertFalse(erc20.isMinterLocked(), "ERC20 minter should not be locked initially");

        // Check if ERC20VotesArbitrator is properly initialized
        ERC20VotesArbitrator erc20VotesArbitrator = ERC20VotesArbitrator(deployedContracts.arbitratorAddress);
        assertEq(erc20VotesArbitrator.owner(), governor, "Arbitrator owner not set correctly");
        assertEq(
            address(erc20VotesArbitrator.votingToken()),
            address(erc20),
            "Voting token not set correctly in Arbitrator"
        );
        assertEq(
            erc20VotesArbitrator._votingPeriod(),
            arbitratorParams.votingPeriod,
            "Voting period not set correctly"
        );
        assertEq(erc20VotesArbitrator._votingDelay(), arbitratorParams.votingDelay, "Voting delay not set correctly");
        assertEq(
            erc20VotesArbitrator._revealPeriod(),
            arbitratorParams.revealPeriod,
            "Reveal period not set correctly"
        );
        assertEq(
            erc20VotesArbitrator._arbitrationCost(),
            arbitratorParams.arbitrationCost,
            "Arbitration cost not set correctly"
        );

        // Check if FlowTCR is properly initialized
        FlowTCR flowTCR = FlowTCR(deployedContracts.tcrAddress);
        assertEq(address(flowTCR.flowContract()), flowContract, "FlowContract not set correctly");
        assertEq(flowTCR.governor(), governor, "Governor not set correctly");
        assertEq(address(flowTCR.tcrFactory()), address(tcrFactory), "TCRFactory not set correctly");

        // Check GeneralizedTCR storage variables
        assertEq(address(flowTCR.arbitrator()), address(flowTCR.arbitrator()), "Arbitrator not set correctly");
        assertEq(
            flowTCR.arbitratorExtraData(),
            flowParams.arbitratorExtraData,
            "arbitratorExtraData not set correctly"
        );
        assertEq(
            flowTCR.registrationMetaEvidence(),
            flowParams.registrationMetaEvidence,
            "registrationMetaEvidence not set correctly"
        );
        assertEq(
            flowTCR.clearingMetaEvidence(),
            flowParams.clearingMetaEvidence,
            "clearingMetaEvidence not set correctly"
        );
        assertEq(address(flowTCR.governor()), flowParams.governor, "Governor not set correctly in GeneralizedTCR");
        assertEq(
            flowTCR.submissionBaseDeposit(),
            flowParams.submissionBaseDeposit,
            "submissionBaseDeposit not set correctly"
        );
        assertEq(flowTCR.removalBaseDeposit(), flowParams.removalBaseDeposit, "removalBaseDeposit not set correctly");
        assertEq(
            flowTCR.submissionChallengeBaseDeposit(),
            flowParams.submissionChallengeBaseDeposit,
            "submissionChallengeBaseDeposit not set correctly"
        );
        assertEq(
            flowTCR.removalChallengeBaseDeposit(),
            flowParams.removalChallengeBaseDeposit,
            "removalChallengeBaseDeposit not set correctly"
        );
        assertEq(
            flowTCR.challengePeriodDuration(),
            flowParams.challengePeriodDuration,
            "challengePeriodDuration not set correctly"
        );

        // Check ERC20 token
        ERC20VotesMintable erc20Token = ERC20VotesMintable(
            address(ERC20VotesArbitrator(address(flowTCR.arbitrator())).votingToken())
        );
        assertTrue(address(erc20Token) != address(0), "ERC20 token not set correctly");
        assertEq(erc20Token.name(), erc20Params.name, "Token name not set correctly");
        assertEq(erc20Token.symbol(), erc20Params.symbol, "Token symbol not set correctly");
        // Assuming ERC20VotesMintable exposes minter and owner
        ERC20VotesMintable mintableToken = ERC20VotesMintable(address(erc20Token));
        assertEq(mintableToken.owner(), erc20Params.initialOwner, "Token initial owner not set correctly");

        // Check Arbitrator
        IArbitrator arbitrator = flowTCR.arbitrator();
        assertTrue(address(arbitrator) != address(0), "Arbitrator address not set correctly");
        // Assuming arbitrator is ERC20VotesArbitrator
        ERC20VotesArbitrator votesArbitrator = ERC20VotesArbitrator(address(arbitrator));
        assertEq(votesArbitrator._votingPeriod(), arbitratorParams.votingPeriod, "Voting period not set correctly");
        assertEq(votesArbitrator._votingDelay(), arbitratorParams.votingDelay, "Voting delay not set correctly");
        assertEq(votesArbitrator._revealPeriod(), arbitratorParams.revealPeriod, "Reveal period not set correctly");
        assertEq(
            votesArbitrator._arbitrationCost(),
            arbitratorParams.arbitrationCost,
            "Arbitration cost not set correctly"
        );
        assertEq(address(votesArbitrator.arbitrable()), address(flowTCR), "Arbitrable not set correctly in arbitrator");
        assertEq(
            address(votesArbitrator.votingToken()),
            address(erc20Token),
            "Voting token not set correctly in arbitrator"
        );
    }
}
