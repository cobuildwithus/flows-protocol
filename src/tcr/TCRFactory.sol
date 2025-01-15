// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IArbitrator } from "./interfaces/IArbitrator.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFlowTCR } from "./interfaces/IGeneralizedTCR.sol";
import { IERC20VotesMintable } from "../interfaces/IERC20VotesMintable.sol";
import { IERC20VotesArbitrator } from "./interfaces/IERC20VotesArbitrator.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ITCRFactory } from "./interfaces/ITCRFactory.sol";
import { IRewardPool } from "../interfaces/IRewardPool.sol";
import { ITokenEmitter } from "../interfaces/ITokenEmitter.sol";
import { GeneralizedTCRStorageV1 } from "./storage/GeneralizedTCRStorageV1.sol";

/**
 * @title TCRFactory
 * @dev Factory contract for deploying and initializing FlowTCR, ERC20VotesArbitrator, and ERC20VotesMintable contracts
 * @notice This contract allows for the creation of new TCR ecosystems with associated arbitration and token contracts
 */
contract TCRFactory is ITCRFactory, Ownable2StepUpgradeable, UUPSUpgradeable {
    /// @notice The address of the FlowTCR implementation contract
    address public flowTCRImplementation;
    /// @notice The address of the ERC20VotesArbitrator implementation contract
    address public arbitratorImplementation;
    /// @notice The address of the ERC20VotesMintable implementation contract
    address public erc20Implementation;
    /// @notice The address of the RewardPool implementation contract
    address public rewardPoolImplementation;
    /// @notice The address of the TokenEmitter implementation contract
    address public tokenEmitterImplementation;
    /// @notice The address of the WETH token
    address public WETH;

    /// @dev Initializer function for the contract
    constructor() initializer {}

    /**
     * @notice Initializes the TCRFactory contract
     * @dev Sets up the contract with an initial owner and deploys implementation contracts
     * @param initialOwner The address that will be set as the initial owner of the contract
     * @param flowTCRImplementation_ The address of the FlowTCR implementation contract
     * @param arbitratorImplementation_ The address of the ERC20VotesArbitrator implementation contract
     * @param erc20Implementation_ The address of the ERC20VotesMintable implementation contract
     * @param rewardPoolImplementation_ The address of the RewardPool implementation contract
     * @param tokenEmitterImplementation_ The address of the TokenEmitter implementation contract
     * @param weth_ The address of the WETH token
     */
    function initialize(
        address initialOwner,
        address flowTCRImplementation_,
        address arbitratorImplementation_,
        address erc20Implementation_,
        address rewardPoolImplementation_,
        address tokenEmitterImplementation_,
        address weth_
    ) public initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        _transferOwnership(initialOwner);

        flowTCRImplementation = flowTCRImplementation_;
        arbitratorImplementation = arbitratorImplementation_;
        erc20Implementation = erc20Implementation_;
        rewardPoolImplementation = rewardPoolImplementation_;
        tokenEmitterImplementation = tokenEmitterImplementation_;
        WETH = weth_;
    }

    /**
     * @notice Deploys a new FlowTCR ecosystem with associated contracts
     * @dev Creates and initializes FlowTCR, ERC20VotesArbitrator, and ERC20VotesMintable contracts
     * @param params Parameters for initializing the FlowTCR contract
     * @param arbitratorParams Parameters for initializing the ERC20VotesArbitrator contract
     * @param erc20Params Parameters for initializing the ERC20VotesMintable contract
     * @return deployedContracts The deployed contracts
     */
    function deployFlowTCR(
        FlowTCRParams memory params,
        ArbitratorParams memory arbitratorParams,
        ERC20Params memory erc20Params,
        RewardPoolParams memory rewardPoolParams,
        TokenEmitterParams memory tokenEmitterParams
    ) external returns (DeployedContracts memory deployedContracts) {
        // Deploy FlowTCR proxy
        address tcrAddress = address(new ERC1967Proxy(flowTCRImplementation, ""));

        // Deploy ERC20VotesArbitrator proxy
        address arbitratorAddress = address(new ERC1967Proxy(arbitratorImplementation, ""));

        // Deploy ERC20VotesMintable proxy
        address erc20Address = address(new ERC1967Proxy(erc20Implementation, ""));

        // Deploy RewardPool proxy
        address rewardPoolAddress = address(new ERC1967Proxy(rewardPoolImplementation, ""));

        // Deploy TokenEmitter proxy
        address tokenEmitterAddress = address(new ERC1967Proxy(tokenEmitterImplementation, ""));

        address[] memory ignoreRewardsAddresses = new address[](2);
        ignoreRewardsAddresses[0] = address(tcrAddress);
        ignoreRewardsAddresses[1] = address(arbitratorAddress);

        // Initialize the ERC20VotesMintable token
        IERC20VotesMintable(erc20Address).initialize({
            initialOwner: erc20Params.initialOwner,
            minter: tokenEmitterAddress,
            rewardPool: rewardPoolAddress,
            ignoreRewardsAddresses: ignoreRewardsAddresses,
            name: erc20Params.name,
            symbol: erc20Params.symbol
        });

        // Initialize the TokenEmitter
        ITokenEmitter(tokenEmitterAddress).initialize({
            weth: WETH,
            erc20: erc20Address,
            basePrice: tokenEmitterParams.basePrice,
            supplyOffset: tokenEmitterParams.supplyOffset,
            initialOwner: params.governor, // Set owner to governor
            curveSteepness: tokenEmitterParams.curveSteepness,
            maxPriceIncrease: tokenEmitterParams.maxPriceIncrease,
            priceDecayPercent: tokenEmitterParams.priceDecayPercent,
            perTimeUnit: tokenEmitterParams.perTimeUnit,
            founderRewardAddress: tokenEmitterParams.founderRewardAddress,
            founderRewardDuration: tokenEmitterParams.founderRewardDuration
        });

        // Initialize the arbitrator
        IERC20VotesArbitrator(arbitratorAddress).initialize({
            initialOwner: params.governor, // Set owner to governor
            votingToken: address(erc20Address),
            arbitrable: tcrAddress,
            votingPeriod: arbitratorParams.votingPeriod,
            votingDelay: arbitratorParams.votingDelay,
            revealPeriod: arbitratorParams.revealPeriod,
            arbitrationCost: arbitratorParams.arbitrationCost
        });

        // Initialize the FlowTCR
        IFlowTCR(tcrAddress).initialize(
            GeneralizedTCRStorageV1.ContractParams({
                initialOwner: params.governor,
                governor: params.governor,
                flowContract: params.flowContract,
                arbitrator: IArbitrator(arbitratorAddress),
                tcrFactory: ITCRFactory(address(this)),
                erc20: IERC20(address(erc20Address))
            }),
            GeneralizedTCRStorageV1.TCRParams({
                submissionBaseDeposit: params.submissionBaseDeposit,
                removalBaseDeposit: params.removalBaseDeposit,
                submissionChallengeBaseDeposit: params.submissionChallengeBaseDeposit,
                removalChallengeBaseDeposit: params.removalChallengeBaseDeposit,
                challengePeriodDuration: params.challengePeriodDuration,
                arbitratorExtraData: params.arbitratorExtraData,
                registrationMetaEvidence: params.registrationMetaEvidence,
                clearingMetaEvidence: params.clearingMetaEvidence,
                requiredRecipientType: params.requiredRecipientType
            }),
            TokenEmitterParams({
                curveSteepness: tokenEmitterParams.curveSteepness,
                basePrice: tokenEmitterParams.basePrice,
                maxPriceIncrease: tokenEmitterParams.maxPriceIncrease,
                supplyOffset: tokenEmitterParams.supplyOffset,
                priceDecayPercent: tokenEmitterParams.priceDecayPercent,
                perTimeUnit: tokenEmitterParams.perTimeUnit,
                founderRewardAddress: tokenEmitterParams.founderRewardAddress,
                founderRewardDuration: tokenEmitterParams.founderRewardDuration
            })
        );

        // Initialize the RewardPool
        IRewardPool(rewardPoolAddress).initialize({
            superToken: rewardPoolParams.superToken,
            manager: erc20Address,
            funder: address(params.flowContract)
        });

        emit FlowTCRDeployed(
            msg.sender,
            tcrAddress,
            arbitratorAddress,
            erc20Address,
            rewardPoolAddress,
            tokenEmitterAddress,
            address(params.flowContract),
            address(params.flowContract.baselinePool()),
            address(params.flowContract.bonusPool())
        );

        deployedContracts = DeployedContracts({
            tcrAddress: tcrAddress,
            arbitratorAddress: arbitratorAddress,
            erc20Address: erc20Address,
            rewardPoolAddress: rewardPoolAddress,
            tokenEmitterAddress: tokenEmitterAddress
        });
    }

    /**
     * @notice Updates the RewardPool implementation address
     * @dev Only callable by the owner
     * @param newImplementation The new implementation address
     */
    function updateRewardPoolImplementation(address newImplementation) external onlyOwner {
        address oldImplementation = rewardPoolImplementation;
        rewardPoolImplementation = newImplementation;
        emit RewardPoolImplementationUpdated(oldImplementation, newImplementation);
    }

    /**
     * @notice Updates the TokenEmitter implementation address
     * @dev Only callable by the owner
     * @param newImplementation The new implementation address
     */
    function updateTokenEmitterImplementation(address newImplementation) external onlyOwner {
        address oldImplementation = tokenEmitterImplementation;
        tokenEmitterImplementation = newImplementation;
        emit TokenEmitterImplementationUpdated(oldImplementation, newImplementation);
    }

    /**
     * @notice Updates the FlowTCR implementation address
     * @dev Only callable by the owner
     * @param newImplementation The new implementation address
     */
    function updateFlowTCRImplementation(address newImplementation) external onlyOwner {
        address oldImplementation = flowTCRImplementation;
        flowTCRImplementation = newImplementation;
        emit FlowTCRImplementationUpdated(oldImplementation, newImplementation);
    }

    /**
     * @notice Updates the ERC20VotesArbitrator implementation address
     * @dev Only callable by the owner
     * @param newImplementation The new implementation address
     */
    function updateArbitratorImplementation(address newImplementation) external onlyOwner {
        address oldImplementation = arbitratorImplementation;
        arbitratorImplementation = newImplementation;
        emit ArbitratorImplementationUpdated(oldImplementation, newImplementation);
    }

    /**
     * @notice Updates the ERC20VotesMintable implementation address
     * @dev Only callable by the owner
     * @param newImplementation The new implementation address
     */
    function updateERC20Implementation(address newImplementation) external onlyOwner {
        address oldImplementation = erc20Implementation;
        erc20Implementation = newImplementation;
        emit ERC20ImplementationUpdated(oldImplementation, newImplementation);
    }

    /**
     * @dev Function to authorize an upgrade to a new implementation
     * @param newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
