// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { IStateProof } from "../interfaces/IStateProof.sol";
import { FlowTypes } from "../storage/FlowStorage.sol";
import { IFlow, ICustomFlow } from "../interfaces/IFlow.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IAllocationStrategy } from "../interfaces/IAllocationStrategy.sol";

library CustomFlowLibrary {
    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function overrides the base _deployFlowRecipient to use CustomFlow-specific initialization
     * @param fs The storage of the CustomFlow contract
     * @param metadata The recipient's metadata like title, description, etc.
     * @param flowManager The address of the flow manager for the new contract
     * @param managerRewardPool The address of the manager reward pool for the new contract
     * @param initialOwner The address of the owner for the new contract
     * @param parent The address of the parent flow contract (optional)
     * @param percentageScale The scale for the percentage of the manager reward pool
     * @param strategies The allocation strategies to use.
     * @return address The address of the newly created Flow contract
     */
    function deployFlowRecipient(
        FlowTypes.Storage storage fs,
        FlowTypes.RecipientMetadata calldata metadata,
        address flowManager,
        address managerRewardPool,
        address initialOwner,
        address parent,
        uint32 percentageScale,
        IAllocationStrategy[] calldata strategies
    ) public returns (address) {
        address flowImpl = fs.flowImpl;
        address recipient = address(new ERC1967Proxy(flowImpl, ""));
        if (recipient == address(0)) revert IFlow.ADDRESS_ZERO();

        // Calculate new manager reward rate, ensuring it doesn't exceed PERCENTAGE_SCALE
        uint32 newManagerRewardRate = fs.managerRewardPoolFlowRatePercent * 2;
        // If doubling would exceed max percentage (percentageScale), cap at max
        if (newManagerRewardRate > percentageScale) {
            newManagerRewardRate = percentageScale;
        }

        ICustomFlow(recipient).initialize({
            initialOwner: initialOwner,
            superToken: address(fs.superToken),
            flowImpl: flowImpl,
            manager: flowManager,
            managerRewardPool: managerRewardPool,
            parent: parent,
            flowParams: IFlow.FlowParams({
                baselinePoolFlowRatePercent: fs.baselinePoolFlowRatePercent,
                managerRewardPoolFlowRatePercent: newManagerRewardRate,
                bonusPoolQuorumBps: fs.bonusPoolQuorumBps
            }),
            metadata: metadata,
            sanctionsOracle: fs.sanctionsOracle,
            strategies: strategies
        });

        return recipient;
    }
}
