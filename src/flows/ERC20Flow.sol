// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { Flow } from "../Flow.sol";
import { IERC20Flow } from "../interfaces/IFlow.sol";
import { FlowVotes } from "../library/FlowVotes.sol";
import { FlowRates } from "../library/FlowRates.sol";
import { IChainalysisSanctionsList } from "../interfaces/external/chainalysis/IChainalysisSanctionsList.sol";
import { IERC20Votes } from "../base/erc20/IERC20Votes.sol";
import { ERC20FlowLibrary } from "../library/ERC20FlowLibrary.sol";

contract ERC20Flow is IERC20Flow, Flow {
    using FlowVotes for Storage;
    using FlowRates for Storage;
    using ERC20FlowLibrary for Storage;

    // The ERC20 voting token contract used to get the voting power of an account
    IERC20Votes public erc20Votes;

    constructor() payable initializer {}

    function initialize(
        address _initialOwner,
        address _superToken,
        address _flowImpl,
        address _manager,
        address _managerRewardPool,
        address _parent,
        FlowParams calldata _flowParams,
        RecipientMetadata calldata _metadata,
        IChainalysisSanctionsList _sanctionsOracle,
        bytes calldata _data
    ) public initializer {
        (address initFlowImpl, address erc20Token) = decodeInitializationData(_data);
        if (initFlowImpl != _flowImpl) revert INVALID_FLOW_IMPL();
        if (erc20Token == address(0)) revert ADDRESS_ZERO();

        erc20Votes = IERC20Votes(erc20Token);

        __Flow_init(
            _initialOwner,
            _superToken,
            _flowImpl,
            _manager,
            _managerRewardPool,
            _parent,
            _flowParams,
            _metadata,
            _sanctionsOracle
        );

        emit ERC20VotingTokenChanged(erc20Token);
    }

    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function is virtual to allow for different deployment strategies in derived contracts
     * @param metadata The recipient's metadata like title, description, etc.
     * @param flowManager The address of the flow manager for the new contract
     * @param managerRewardPool The address of the manager reward pool for the new contract
     * @param initializationData The initialization data for the new contract
     * @return recipient address The address of the newly created Flow contract
     */
    function _deployFlowRecipient(
        RecipientMetadata calldata metadata,
        address flowManager,
        address managerRewardPool,
        bytes calldata initializationData
    ) internal override returns (address recipient) {
        bytes memory data = initializationData.length > 0
            ? initializationData
            : abi.encode(fs.flowImpl, address(erc20Votes));

        recipient = fs.deployFlowRecipient(
            metadata,
            flowManager,
            managerRewardPool,
            owner(),
            address(this),
            PERCENTAGE_SCALE,
            data
        );
    }

    /**
     * @notice Function to calculate the total vote weight of all tokens used for voting
     * @dev This function can be overridden in derived contracts to implement custom logic
     * @return uint256 The total vote weight of all tokens used for voting
     */
    function totalTokenSupplyVoteWeight() public view override returns (uint256) {
        return erc20Votes.totalSupply() * fs.tokenVoteWeight;
    }

    /**
     * @notice Decodes the initialization data
     * @param data The initialization data
     * @return flowImpl The address of the flow implementation for the deployed child contract
     * @return erc20Token The address of the ERC20 token used for voting
     */
    function decodeInitializationData(bytes calldata data) public pure returns (address flowImpl, address erc20Token) {
        (flowImpl, erc20Token) = abi.decode(data, (address, address));
    }
}
