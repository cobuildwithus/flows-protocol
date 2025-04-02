// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { IStateProof } from "../interfaces/IStateProof.sol";
import { FlowTypes } from "../storage/FlowStorage.sol";
import { IERC721Flow, IFlow } from "../interfaces/IFlow.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

library ERC721FlowLibrary {
    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function overrides the base _deployFlowRecipient to use ERC721Flow-specific initialization
     * @param fs The storage of the ERC721Flow contract
     * @param metadata The recipient's metadata like title, description, etc.
     * @param flowManager The address of the flow manager for the new contract
     * @param managerRewardPool The address of the manager reward pool for the new contract
     * @param initialOwner The address of the owner for the new contract
     * @param parent The address of the parent flow contract (optional)
     * @param erc721Votes The address of the ERC721Votes contract
     * @param percentageScale The scale for the percentage of the manager reward pool
     * @return address The address of the newly created Flow contract
     */
    function deployFlowRecipient(
        FlowTypes.Storage storage fs,
        FlowTypes.RecipientMetadata calldata metadata,
        address flowManager,
        address managerRewardPool,
        address initialOwner,
        address parent,
        address erc721Votes,
        uint32 percentageScale
    ) public returns (address) {
        address recipient = address(new ERC1967Proxy(fs.flowImpl, ""));
        if (recipient == address(0)) revert IFlow.ADDRESS_ZERO();

        // Calculate new manager reward rate, ensuring it doesn't exceed PERCENTAGE_SCALE
        uint32 newManagerRewardRate = fs.managerRewardPoolFlowRatePercent * 2;
        // If doubling would exceed max percentage (percentageScale), cap at max
        if (newManagerRewardRate > percentageScale) {
            newManagerRewardRate = percentageScale;
        }

        IERC721Flow(recipient).initialize({
            initialOwner: initialOwner,
            nounsToken: erc721Votes,
            superToken: address(fs.superToken),
            flowImpl: fs.flowImpl,
            manager: flowManager,
            managerRewardPool: managerRewardPool,
            parent: parent,
            flowParams: IFlow.FlowParams({
                tokenVoteWeight: fs.tokenVoteWeight,
                baselinePoolFlowRatePercent: fs.baselinePoolFlowRatePercent,
                managerRewardPoolFlowRatePercent: newManagerRewardRate,
                bonusPoolQuorumBps: fs.bonusPoolQuorumBps
            }),
            metadata: metadata,
            sanctionsOracle: fs.sanctionsOracle
        });

        return recipient;
    }
}
