// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { GeneralizedTCR } from "./GeneralizedTCR.sol";
import { IArbitrator } from "./interfaces/IArbitrator.sol";
import { IManagedFlow } from "../interfaces/IManagedFlow.sol";
import { IFlowTCR } from "./interfaces/IGeneralizedTCR.sol";
import { FlowTypes } from "../storage/FlowStorage.sol";
import { ITCRFactory } from "./interfaces/ITCRFactory.sol";
import { FlowTCRItems } from "./library/FlowTCRItems.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

/**
 * @title FlowTCR
 * @dev This contract extends GeneralizedTCR to provide a Token Curated Registry (TCR)
 * specifically designed to interface with the Flow.sol contract as a manager.
 * It allows for the curation of recipients in the Flow ecosystem through a
 * decentralized voting and challenge process.
 */
contract FlowTCR is GeneralizedTCR, IFlowTCR {
    using FlowTCRItems for bytes;

    // The Flow contract this TCR is managing
    IManagedFlow public flowContract;

    // The address of the TCR factory
    ITCRFactory public tcrFactory;

    // The required FlowRecipient type for the TCR (optional)
    FlowTypes.RecipientType public requiredRecipientType;

    // TokenEmitter parameters
    int256 public curveSteepness;
    int256 public basePrice;
    int256 public maxPriceIncrease;
    int256 public supplyOffset;
    // TokenEmitter VRGDACap parameters
    int256 public priceDecayPercent;
    int256 public perTimeUnit;
    // The founder reward params
    address public founderRewardAddress;
    uint256 public founderRewardDuration;

    // Error emitted when the curve steepness is invalid
    error INVALID_CURVE_STEEPNESS();

    // Event emitted when TokenEmitter parameters are set
    event TokenEmitterParamsSet(
        int256 curveSteepness,
        int256 basePrice,
        int256 maxPriceIncrease,
        int256 supplyOffset,
        int256 priceDecayPercent,
        int256 perTimeUnit,
        address founderRewardAddress,
        uint256 founderRewardDuration
    );

    // Event emitted when the required recipient type is set
    event RequiredRecipientTypeSet(FlowTypes.RecipientType requiredRecipientType);

    constructor() payable initializer {}

    /**
     * @dev Initializes the FlowTCR contract with necessary parameters and links it to a Flow contract.
     * @param _contractParams Struct containing address parameters and interfaces
     * @param _tcrParams Struct containing TCR parameters, including deposits, durations, and evidence
     */
    function initialize(
        ContractParams memory _contractParams,
        TCRParams memory _tcrParams,
        ITCRFactory.TokenEmitterParams memory _tokenEmitterParams
    ) public initializer {
        flowContract = _contractParams.flowContract;
        tcrFactory = _contractParams.tcrFactory;
        requiredRecipientType = _tcrParams.requiredRecipientType;

        _setTokenEmitterParams(
            _tokenEmitterParams.curveSteepness,
            _tokenEmitterParams.basePrice,
            _tokenEmitterParams.maxPriceIncrease,
            _tokenEmitterParams.supplyOffset,
            _tokenEmitterParams.priceDecayPercent,
            _tokenEmitterParams.perTimeUnit,
            _tokenEmitterParams.founderRewardAddress,
            _tokenEmitterParams.founderRewardDuration
        );

        __GeneralizedTCR_init(
            _contractParams.initialOwner,
            _contractParams.arbitrator,
            _tcrParams.arbitratorExtraData,
            _tcrParams.registrationMetaEvidence,
            _tcrParams.clearingMetaEvidence,
            _contractParams.governor,
            _contractParams.erc20,
            _tcrParams.submissionBaseDeposit,
            _tcrParams.removalBaseDeposit,
            _tcrParams.submissionChallengeBaseDeposit,
            _tcrParams.removalChallengeBaseDeposit,
            _tcrParams.challengePeriodDuration
        );
    }

    /**
     * @notice Removes an item from the Flow contract when it's removed from the TCR
     * @param _itemID The ID of the item being removed
     * @dev This function is called internally when an item is removed from the TCR
     * @dev IMPORTANT: Assumes that the itemID is consistent with the recipientId in the Flow contract
     */
    function _onItemRemoved(bytes32 _itemID) internal override {
        flowContract.removeRecipient(_itemID);
    }

    /**
     * @notice Construct the itemID from the item data.
     * @return itemID The ID of the item.
     */
    function _constructNewItemID(bytes calldata) internal override returns (bytes32 itemID) {
        itemID = keccak256(abi.encode(address(this), itemList.length)); // Ensures uniqueness across contracts
    }

    /**
     * @dev Verifies the data of an item before it's added to the registry.
     * @param _item The data describing the item to be added.
     * @return valid True if the item data is valid, false otherwise.
     */
    function _verifyItemData(bytes calldata _item) internal view override returns (bool valid) {
        valid = _item.verifyItemData(requiredRecipientType, flowContract);
    }

    /**
     * @notice Handles the registration of an item in the TCR
     * @param _itemID The ID of the item being registered
     * @param _item The data describing the item
     * @dev This function is called internally when an item is registered in the TCR
     */
    function _onItemRegistered(bytes32 _itemID, bytes memory _item) internal override {
        // Decode the item data
        (address recipient, FlowTypes.RecipientMetadata memory metadata, FlowTypes.RecipientType recipientType) = _item
            .decodeItemData();

        // So we can reuse IDs across contracts and easily remove the recipient from the Flow
        // If it's cleared from the TCR
        bytes32 recipientId = _itemID;

        // Add the recipient to the Flow contract
        if (recipientType == FlowTypes.RecipientType.ExternalAccount) {
            flowContract.addRecipient(recipientId, recipient, metadata);
        } else if (recipientType == FlowTypes.RecipientType.FlowContract) {
            // temporarily set manager to this contract so we can set the reward pool and actual TCR manager after they're deployed
            // make sure address(this) is updated!
            (, address flowRecipient) = flowContract.addFlowRecipient(
                recipientId,
                metadata,
                address(this),
                address(0) // set to 0 so Flow doesn't try to set the reward pool flow rate on a TCR contract
            );

            ITCRFactory.DeployedContracts memory deployedContracts = tcrFactory.deployFlowTCR(
                ITCRFactory.FlowTCRParams({
                    flowContract: IManagedFlow(flowRecipient),
                    arbitratorExtraData: arbitratorExtraData,
                    registrationMetaEvidence: registrationMetaEvidence,
                    clearingMetaEvidence: clearingMetaEvidence,
                    governor: governor,
                    submissionBaseDeposit: submissionBaseDeposit,
                    removalBaseDeposit: removalBaseDeposit,
                    submissionChallengeBaseDeposit: submissionChallengeBaseDeposit,
                    removalChallengeBaseDeposit: removalChallengeBaseDeposit,
                    challengePeriodDuration: challengePeriodDuration,
                    requiredRecipientType: FlowTypes.RecipientType.ExternalAccount // children are not flows for now, TODO make this configurable
                }),
                arbitrator.getArbitratorParamsForFactory(),
                ITCRFactory.ERC20Params({ initialOwner: owner(), name: metadata.title, symbol: "TCR" }), // TODO update all
                ITCRFactory.RewardPoolParams({ superToken: ISuperToken(flowContract.getSuperToken()) }),
                ITCRFactory.TokenEmitterParams({
                    curveSteepness: curveSteepness,
                    // scale down by 10 so children don't have the same economic expectations as their parent
                    // so eg: tokens are 10x cheaper but follow same curve for children
                    basePrice: basePrice / 10,
                    maxPriceIncrease: maxPriceIncrease / 10,
                    supplyOffset: supplyOffset,
                    priceDecayPercent: priceDecayPercent,
                    // since children will likely have many more applications
                    // we want to raise the ceiling
                    perTimeUnit: perTimeUnit * 2,
                    founderRewardAddress: founderRewardAddress,
                    founderRewardDuration: founderRewardDuration
                })
            );

            // set manager on the newly created Flow contract to the new TCR and manager reward pool
            // can only be done by the manager
            IManagedFlow(flowRecipient).setManagerRewardPool(deployedContracts.rewardPoolAddress);
            // now that the reward pool is set, we set the flow rate for it
            IManagedFlow(flowRecipient).resetFlowRate();
            // now that the reward pool is set, we can set the actual manager
            IManagedFlow(flowRecipient).setManager(deployedContracts.tcrAddress);
        }
    }

    /**
     * @notice Sets the required recipient type for the TCR
     * @param _requiredRecipientType The required recipient type
     * @dev This function is called internally when the required recipient type is set
     */
    function setRequiredRecipientType(FlowTypes.RecipientType _requiredRecipientType) external onlyOwner {
        requiredRecipientType = _requiredRecipientType;
        emit RequiredRecipientTypeSet(_requiredRecipientType);
    }

    /**
     * @notice Sets the TokenEmitter parameters
     * @param _curveSteepness The steepness of the curve
     * @param _basePrice The base price for a token if sold on pace
     * @param _maxPriceIncrease The maximum price increase for a token if sold on pace
     * @param _supplyOffset The supply offset for a token if sold on pace
     * @param _priceDecayPercent The price decay percent for the VRGDACap
     * @param _perTimeUnit The per time unit for the VRGDACap
     * @param _founderRewardAddress The address of the founder reward
     * @param _founderRewardDuration The expiration of the founder reward
     */
    function setTokenEmitterParams(
        int256 _curveSteepness,
        int256 _basePrice,
        int256 _maxPriceIncrease,
        int256 _supplyOffset,
        int256 _priceDecayPercent,
        int256 _perTimeUnit,
        address _founderRewardAddress,
        uint256 _founderRewardDuration
    ) external onlyOwner {
        _setTokenEmitterParams(
            _curveSteepness,
            _basePrice,
            _maxPriceIncrease,
            _supplyOffset,
            _priceDecayPercent,
            _perTimeUnit,
            _founderRewardAddress,
            _founderRewardDuration
        );
    }

    /**
     * @notice Internal function to set the TokenEmitter parameters
     * @param _curveSteepness The steepness of the curve
     * @param _basePrice The base price for a token if sold on pace
     * @param _maxPriceIncrease The maximum price increase for a token if sold on pace
     * @param _supplyOffset The supply offset for a token if sold on pace
     * @param _priceDecayPercent The price decay percent for the VRGDACap
     * @param _perTimeUnit The per time unit for the VRGDACap
     * @param _founderRewardAddress The address of the founder reward
     * @param _founderRewardDuration The expiration of the founder reward
     */
    function _setTokenEmitterParams(
        int256 _curveSteepness,
        int256 _basePrice,
        int256 _maxPriceIncrease,
        int256 _supplyOffset,
        int256 _priceDecayPercent,
        int256 _perTimeUnit,
        address _founderRewardAddress,
        uint256 _founderRewardDuration
    ) internal {
        if (_curveSteepness <= 0) revert INVALID_CURVE_STEEPNESS();

        curveSteepness = _curveSteepness;
        basePrice = _basePrice;
        maxPriceIncrease = _maxPriceIncrease;
        supplyOffset = _supplyOffset;
        priceDecayPercent = _priceDecayPercent;
        perTimeUnit = _perTimeUnit;
        founderRewardAddress = _founderRewardAddress;
        founderRewardDuration = _founderRewardDuration;

        emit TokenEmitterParamsSet(
            _curveSteepness,
            _basePrice,
            _maxPriceIncrease,
            _supplyOffset,
            _priceDecayPercent,
            _perTimeUnit,
            _founderRewardAddress,
            _founderRewardDuration
        );
    }
}
