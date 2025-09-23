// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { IResolver } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/utils/IResolver.sol";
import { IFlow } from "./IFlow.sol";
import { FlowTypes } from "../storage/FlowStorage.sol";
import { IChainalysisSanctionsList } from "./external/chainalysis/IChainalysisSanctionsList.sol";

interface IFlowDeployer {
    // ---- Errors ----
    error NoCanonicalWrapper(address underlying);
    error SuperfluidHostNotFound();

    error ResolverZeroAddress();
    error CustomFlowImplZeroAddress();
    error StrategyImplZeroAddress();
    error InitialOwnerZeroAddress();
    error ConnectPoolAdminZeroAddress();
    error ManagerRewardPoolZeroAddress();
    error SanctionsOracleZeroAddress();

    error ResolverNotContract(address resolver);
    error CustomFlowImplNotContract(address impl);
    error StrategyImplNotContract(address impl);

    error AllocatorZeroAddress();
    error ManagerZeroAddress();
    error UnderlyingZeroAddress();

    error UnderlyingNotContract(address underlying);
    error HostNotContract(address host);
    error FactoryNotContract(address factory);

    // NEW: fallback/recording errors
    error NonCanonicalCreationFailed(address underlying, bytes reason);
    error WrapperAlreadyRecorded(address underlying, address existing);
    error InvalidWrapper(address underlying, address superToken);
    error NotSuperToken(address superToken);
    error SanctionsOracleNotContract(address oracle);
    error InvalidManagerRewardPercent();
    error UnderlyingIsSuperToken(address token);
    error UnderlyingLacksERC20Metadata(address underlying);

    // ---- Types ----
    struct DeployParams {
        address manager;
        address underlyingERC20;
        address allocator;
        IFlow.FlowParams flowParams;
        FlowTypes.RecipientMetadata metadata;
    }

    // ---- Events ----
    event NonCanonicalWrapperCreated(
        address indexed underlying,
        address indexed superToken,
        string name,
        string symbol,
        uint8 decimals
    );
    event WrapperRecorded(address indexed underlying, address indexed superToken);

    /// @notice Emitted when the shared CustomFlow implementation is updated
    event CustomFlowImplUpdated(address oldImplementation, address newImplementation);

    /// @notice Emitted when the shared SingleAllocatorStrategy implementation is updated
    event SingleAllocatorStrategyImplUpdated(address oldImplementation, address newImplementation);

    /// @notice Emitted when the manager reward pool address is updated
    event ManagerRewardPoolUpdated(address indexed oldManagerRewardPool, address indexed newManagerRewardPool);

    /// @notice Emitted when the manager reward pool flow rate percent is updated
    event ManagerRewardFlowRatePercentUpdated(
        uint32 oldManagerRewardFlowRatePercent,
        uint32 newManagerRewardFlowRatePercent
    );

    /// @notice Emitted when the sanctions oracle is updated
    event SanctionsOracleUpdated(address oldOracle, address newOracle);

    /// @notice Emitted when the connect pool admin is updated
    event ConnectPoolAdminUpdated(address indexed oldConnectPoolAdmin, address indexed newConnectPoolAdmin);

    // ---- API ----
    function initialize(
        IResolver _resolver,
        address _customFlowImpl,
        address _singleAllocatorStrategyImpl,
        address _initialOwner,
        address _connectPoolAdmin,
        address _managerRewardPool,
        uint32 _managerRewardPoolFlowRatePercent,
        IChainalysisSanctionsList _sanctionsOracle
    ) external;

    function deployFlow(DeployParams calldata params) external returns (address flow, address strategy);

    /// Canonical-only (may revert)
    function getCanonicalWrapper(address underlying) external view returns (address superToken);

    /// NEW: canonical if present else recorded non-canonical
    function getWrapper(address underlying) external view returns (address superToken, bool isCanonical);

    /// NEW: record an already deployed non-canonical wrapper (owner only)
    function recordWrapper(address underlying, address superToken) external;

    /// @notice Update the shared `CustomFlow` implementation used for new deployments
    /// @param newImplementation Address of the new `CustomFlow` implementation
    function setCustomFlowImpl(address newImplementation) external;

    /// @notice Update the shared `SingleAllocatorStrategy` implementation used for new deployments
    /// @param newImplementation Address of the new `SingleAllocatorStrategy` implementation
    function setSingleAllocatorStrategyImpl(address newImplementation) external;

    /// @notice Update the fixed connect pool admin address applied to new flows
    /// @param newConnectPoolAdmin New connect pool admin
    function setConnectPoolAdmin(address newConnectPoolAdmin) external;

    /// @notice Update the fixed manager reward pool address applied to new flows
    /// @param newManagerRewardPool New manager reward pool address
    function setManagerRewardPool(address newManagerRewardPool) external;

    /// @notice Update the fixed manager reward pool flow rate percent (PPM scale)
    /// @param newManagerRewardPoolFlowRatePercent New percent in PPM (<= 1e6)
    function setManagerRewardFlowRatePercent(uint32 newManagerRewardPoolFlowRatePercent) external;

    /// @notice Update the fixed sanctions oracle applied to new flows
    /// @param newSanctionsOracle New sanctions oracle contract
    function setSanctionsOracle(IChainalysisSanctionsList newSanctionsOracle) external;
}
