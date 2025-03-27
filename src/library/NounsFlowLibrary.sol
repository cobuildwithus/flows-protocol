// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { IStateProof } from "../interfaces/IStateProof.sol";
import { FlowTypes } from "../storage/FlowStorage.sol";
import { INounsFlow, IFlow } from "../interfaces/IFlow.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

library NounsFlowLibrary {
    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function overrides the base _deployFlowRecipient to use NounsFlow-specific initialization
     * @param fs The storage of the NounsFlow contract
     * @param metadata The recipient's metadata like title, description, etc.
     * @param flowManager The address of the flow manager for the new contract
     * @param managerRewardPool The address of the manager reward pool for the new contract
     * @param verifier The address of the verifier for the new contract
     * @param initialOwner The address of the owner for the new contract
     * @param parent The address of the parent flow contract (optional)
     * @param percentageScale The scale of the percentage (optional)
     * @return address The address of the newly created Flow contract
     */
    function deployFlowRecipient(
        FlowTypes.Storage storage fs,
        FlowTypes.RecipientMetadata calldata metadata,
        address flowManager,
        address managerRewardPool,
        address verifier,
        address initialOwner,
        address parent,
        uint32 percentageScale
    ) public returns (address) {
        address recipient = address(new ERC1967Proxy(fs.flowImpl, ""));
        if (recipient == address(0)) revert IFlow.ADDRESS_ZERO();

        uint32 managerRewardPoolFlowRatePercent = fs.managerRewardPoolFlowRatePercent * 2;

        if (managerRewardPoolFlowRatePercent > percentageScale) managerRewardPoolFlowRatePercent = percentageScale;

        INounsFlow(recipient).initialize({
            initialOwner: initialOwner,
            verifier: verifier,
            superToken: address(fs.superToken),
            flowImpl: fs.flowImpl,
            manager: flowManager,
            managerRewardPool: managerRewardPool,
            parent: parent,
            flowParams: IFlow.FlowParams({
                tokenVoteWeight: fs.tokenVoteWeight,
                baselinePoolFlowRatePercent: fs.baselinePoolFlowRatePercent,
                managerRewardPoolFlowRatePercent: managerRewardPoolFlowRatePercent
            }),
            metadata: metadata
        });

        return recipient;
    }
}
