// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IResolver } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/utils/IResolver.sol";
import { ISuperfluid } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ISuperTokenFactory } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperTokenFactory.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import { ICustomFlow, IFlow } from "./interfaces/IFlow.sol";
import { IFlowDeployer } from "./interfaces/IFlowDeployer.sol";
import { FlowTypes } from "./storage/FlowStorage.sol";
import { IAllocationStrategy } from "./interfaces/IAllocationStrategy.sol";
import { IChainalysisSanctionsList } from "./interfaces/external/chainalysis/IChainalysisSanctionsList.sol";

import { SingleAllocatorStrategy } from "./allocation-strategies/SingleAllocatorStrategy.sol";

/// @title FlowDeployer
/// @notice Deploys `CustomFlow` proxies using the canonical SuperToken wrapper for a given ERC20
contract FlowDeployer is IFlowDeployer, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    /// @notice Superfluid resolver (used to discover Host and SuperTokenFactory)
    IResolver public resolver;

    /// @notice Address of the shared `CustomFlow` implementation
    address public customFlowImpl;

    /// @notice Address of the shared `SingleAllocatorStrategy` implementation
    address public singleAllocatorStrategyImpl;

    /// @notice Fixed connect pool admin for flows
    address public connectPoolAdmin;

    /// @notice Fixed manager reward pool for flows
    address public managerRewardPool;

    /// @notice Fixed manager reward pool flow rate percent (PPM-scale per IFlow.PERCENTAGE_SCALE)
    uint32 public managerRewardPoolFlowRatePercent;

    /// @notice Fixed sanctions oracle for all flows
    IChainalysisSanctionsList public sanctionsOracle;

    /// @notice Cache of deployed SingleAllocatorStrategy proxies keyed by allocator
    mapping(address => address) public allocatorToStrategy;

    /// NEW: record only non‑canonical wrappers we create or record manually
    mapping(address => address) public nonCanonicalWrapper;

    /// @notice Superfluid release string used in resolver lookups (e.g. "Superfluid.v1")
    string public constant SUPERFLUID_RELEASE = "v1";

    /// @notice Error definitions are declared in IFlowDeployer

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the deployer configuration
    /// @param _resolver Superfluid resolver address for the target network
    /// @param _customFlowImpl Address of the deployed `CustomFlow` implementation
    /// @param _singleAllocatorStrategyImpl Address of the deployed `SingleAllocatorStrategy` implementation
    /// @param _initialOwner Fixed initial owner for strategies and flows
    /// @param _connectPoolAdmin Fixed pool admin that can connect pools
    /// @param _managerRewardPool Fixed manager reward pool address
    function initialize(
        IResolver _resolver,
        address _customFlowImpl,
        address _singleAllocatorStrategyImpl,
        address _initialOwner,
        address _connectPoolAdmin,
        address _managerRewardPool,
        uint32 _managerRewardPoolFlowRatePercent,
        IChainalysisSanctionsList _sanctionsOracle
    ) external initializer {
        if (address(_resolver) == address(0)) revert ResolverZeroAddress();
        if (_customFlowImpl == address(0)) revert CustomFlowImplZeroAddress();
        if (_singleAllocatorStrategyImpl == address(0)) revert StrategyImplZeroAddress();
        if (_initialOwner == address(0)) revert InitialOwnerZeroAddress();
        if (_connectPoolAdmin == address(0)) revert ConnectPoolAdminZeroAddress();
        if (_managerRewardPool == address(0)) revert ManagerRewardPoolZeroAddress();
        if (address(_sanctionsOracle) == address(0)) revert SanctionsOracleZeroAddress();

        if (address(_resolver).code.length == 0) revert ResolverNotContract(address(_resolver));
        if (_customFlowImpl.code.length == 0) revert CustomFlowImplNotContract(_customFlowImpl);
        if (_singleAllocatorStrategyImpl.code.length == 0) revert StrategyImplNotContract(_singleAllocatorStrategyImpl);
        if (address(_sanctionsOracle).code.length == 0) revert SanctionsOracleNotContract(address(_sanctionsOracle));

        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        _transferOwnership(_initialOwner);

        // Cap manager reward percent to PERCENTAGE_SCALE (1e6) to avoid invalid flow math
        if (_managerRewardPoolFlowRatePercent > 1_000_000) revert InvalidManagerRewardPercent();
        resolver = _resolver;
        customFlowImpl = _customFlowImpl;
        singleAllocatorStrategyImpl = _singleAllocatorStrategyImpl;
        connectPoolAdmin = _connectPoolAdmin;
        managerRewardPool = _managerRewardPool;
        managerRewardPoolFlowRatePercent = _managerRewardPoolFlowRatePercent;
        sanctionsOracle = _sanctionsOracle;
    }

    /// @notice Deploy a new `CustomFlow` using the canonical SuperToken wrapper of `underlyingERC20`
    /// @param params Consolidated deployment parameters
    /// @return flow Address of the deployed CustomFlow proxy
    /// @return strategy Address of the deployed SingleAllocatorStrategy proxy (top-level strategy)
    function deployFlow(
        IFlowDeployer.DeployParams calldata params
    ) external nonReentrant returns (address flow, address strategy) {
        if (params.allocator == address(0)) revert AllocatorZeroAddress();
        if (params.manager == address(0)) revert ManagerZeroAddress();
        if (params.underlyingERC20 == address(0)) revert UnderlyingZeroAddress();
        address superToken = _getOrCreateWrapper(params.underlyingERC20);

        // Reuse SingleAllocatorStrategy by allocator when available; otherwise deploy & cache
        address cached = allocatorToStrategy[params.allocator];
        if (cached == address(0)) {
            bytes memory strategyInitData = abi.encodeCall(
                SingleAllocatorStrategy.initialize,
                (owner(), params.allocator)
            );
            strategy = address(new ERC1967Proxy(singleAllocatorStrategyImpl, strategyInitData));
            allocatorToStrategy[params.allocator] = strategy;
        } else {
            strategy = cached;
        }

        IAllocationStrategy[] memory strategies = new IAllocationStrategy[](1);
        strategies[0] = IAllocationStrategy(strategy);

        // Initialize CustomFlow via proxy, overriding managerRewardPoolFlowRatePercent and sanctions oracle
        bytes memory initData = abi.encodeCall(
            ICustomFlow.initialize,
            (
                owner(),
                superToken,
                customFlowImpl,
                params.manager,
                managerRewardPool,
                address(0),
                connectPoolAdmin,
                IFlow.FlowParams({
                    baselinePoolFlowRatePercent: params.flowParams.baselinePoolFlowRatePercent,
                    managerRewardPoolFlowRatePercent: managerRewardPoolFlowRatePercent,
                    bonusPoolQuorumBps: params.flowParams.bonusPoolQuorumBps
                }),
                params.metadata,
                sanctionsOracle,
                strategies
            )
        );

        flow = address(new ERC1967Proxy(customFlowImpl, initData));
    }

    /// @notice Resolve the canonical SuperToken wrapper for an underlying ERC20
    /// @param underlying Address of the underlying ERC20 token
    /// @return superToken Address of the canonical SuperToken wrapper
    function getCanonicalWrapper(address underlying) external view returns (address superToken) {
        superToken = _getCanonicalWrapper(underlying);
    }

    /// NEW: canonical if present else recorded non-canonical
    function getWrapper(address underlying) external view returns (address superToken, bool isCanonical) {
        ISuperfluid host = _getHost();
        if (address(host).code.length == 0) revert HostNotContract(address(host));
        ISuperTokenFactory factory = host.getSuperTokenFactory();
        if (address(factory).code.length == 0) revert FactoryNotContract(address(factory));

        superToken = factory.getCanonicalERC20Wrapper(underlying);
        if (superToken != address(0)) return (superToken, true);

        superToken = nonCanonicalWrapper[underlying];
        return (superToken, false);
    }

    /// NEW: owner can record an already deployed non-canonical wrapper (off-chain discovered)
    function recordWrapper(address underlying, address superToken) external onlyOwner {
        if (underlying == address(0)) revert UnderlyingZeroAddress();
        if (superToken == address(0)) revert NotSuperToken(address(0));
        if (superToken.code.length == 0) revert NotSuperToken(superToken);
        // prevent recording if a canonical wrapper already exists
        {
            ISuperfluid host = _getHost();
            if (address(host).code.length == 0) revert HostNotContract(address(host));
            ISuperTokenFactory factory = host.getSuperTokenFactory();
            if (address(factory).code.length == 0) revert FactoryNotContract(address(factory));
            address canonical = factory.getCanonicalERC20Wrapper(underlying);
            if (canonical != address(0)) {
                revert WrapperAlreadyRecorded(underlying, canonical);
            }
        }
        if (nonCanonicalWrapper[underlying] != address(0))
            revert WrapperAlreadyRecorded(underlying, nonCanonicalWrapper[underlying]);

        // sanity: verify underlying matches wrapper
        address u;
        try ISuperToken(superToken).getUnderlyingToken() returns (address _u) {
            u = _u;
        } catch {}
        // If getUnderlyingToken() is not implemented (pure SuperToken), reject:
        if (u == address(0) || u != underlying) revert InvalidWrapper(underlying, superToken);

        nonCanonicalWrapper[underlying] = superToken;
        emit WrapperRecorded(underlying, superToken);
    }

    function _getCanonicalWrapper(address underlying) internal view returns (address superToken) {
        ISuperfluid host = _getHost();
        if (address(host).code.length == 0) revert HostNotContract(address(host));
        ISuperTokenFactory factory = host.getSuperTokenFactory();
        if (address(factory).code.length == 0) revert FactoryNotContract(address(factory));
        superToken = factory.getCanonicalERC20Wrapper(underlying);
        if (superToken == address(0)) revert NoCanonicalWrapper(underlying);
    }

    /// @dev Append a trailing 'x' to the symbol unless it already ends with 'x' or 'X'
    function _appendX(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        if (b.length > 0) {
            bytes1 last = b[b.length - 1];
            if (last == 0x78 || last == 0x58) {
                return s;
            }
        }
        return string.concat(s, "x");
    }

    /// NEW: canonical-first, then non‑canonical fallback and record it
    function _getOrCreateWrapper(address underlying) internal returns (address superToken) {
        // Preflight checks for better diagnostics
        if (underlying == address(0)) revert UnderlyingZeroAddress();
        if (underlying.code.length == 0) revert UnderlyingNotContract(underlying);

        // Optional clarity: reject if underlying is already a SuperToken
        // This uses a try/catch to avoid reverting on non-SuperTokens
        try ISuperToken(underlying).getUnderlyingToken() returns (address) {
            // If call succeeds, it's a SuperToken
            revert UnderlyingIsSuperToken(underlying);
        } catch {}

        ISuperfluid host = _getHost();
        if (address(host).code.length == 0) revert HostNotContract(address(host));

        ISuperTokenFactory factory = host.getSuperTokenFactory();
        if (address(factory).code.length == 0) revert FactoryNotContract(address(factory));

        // 0) canonical exists?
        superToken = factory.getCanonicalERC20Wrapper(underlying);
        if (superToken != address(0)) return superToken;

        // 1) recorded non-canonical?
        address recorded = nonCanonicalWrapper[underlying];
        if (recorded != address(0)) return recorded;

        // 2) If predicted exists (registered & deployed), use it
        (address predicted, bool isDeployed) = factory.computeCanonicalERC20WrapperAddress(underlying);
        if (isDeployed) return predicted;

        // 3) Otherwise create canonical; handle race conditions
        try factory.createCanonicalERC20Wrapper(IERC20Metadata(underlying)) returns (ISuperToken st) {
            return address(st);
        } catch (bytes memory /*reason*/) {
            // Re-check after possible race
            superToken = factory.getCanonicalERC20Wrapper(underlying);
            if (superToken != address(0)) return superToken;

            (predicted, isDeployed) = factory.computeCanonicalERC20WrapperAddress(underlying);
            if (isDeployed) return predicted;

            // 4) fallback: create non‑canonical wrapper and record it
            // Validate ERC20Metadata presence explicitly for clearer erroring and
            // tolerate non-standard name/symbol implementations
            string memory n;
            try IERC20Metadata(underlying).name() returns (string memory _n) {
                n = _n;
            } catch {
                n = "";
            }

            string memory s;
            try IERC20Metadata(underlying).symbol() returns (string memory _s) {
                s = _s;
            } catch {
                s = "";
            }

            uint8 d;
            try IERC20Metadata(underlying).decimals() returns (uint8 _d) {
                d = _d;
            } catch {
                revert UnderlyingLacksERC20Metadata(underlying);
            }

            // If name/symbol missing, pick sensible defaults.
            string memory finalName = bytes(n).length != 0 ? string.concat("Super ", n) : "Super Token";
            string memory finalSymbol = bytes(s).length != 0 ? _appendX(s) : "STX";

            // Use SEMI_UPGRADABLE per canonical standard
            try
                factory.createERC20Wrapper(
                    IERC20Metadata(underlying),
                    d,
                    ISuperTokenFactory.Upgradability.SEMI_UPGRADABLE,
                    finalName,
                    finalSymbol
                )
            returns (ISuperToken st2) {
                address nonCanon = address(st2);
                nonCanonicalWrapper[underlying] = nonCanon;
                emit NonCanonicalWrapperCreated(underlying, nonCanon, finalName, finalSymbol, d);
                return nonCanon;
            } catch (bytes memory reason2) {
                revert NonCanonicalCreationFailed(underlying, reason2);
            }
        }
    }

    function _getHost() internal view returns (ISuperfluid) {
        address h = resolver.get(string.concat("Superfluid.", SUPERFLUID_RELEASE));
        if (h == address(0)) {
            // Fallback for Superfluid test deployments
            h = resolver.get("Superfluid.test");
        }
        if (h == address(0)) revert SuperfluidHostNotFound();
        return ISuperfluid(h);
    }

    // ---- Owner setters ----

    /// @notice Update the shared `CustomFlow` implementation used for new deployments
    /// @param newImplementation Address of the new `CustomFlow` implementation
    function setCustomFlowImpl(address newImplementation) external onlyOwner {
        if (newImplementation == address(0)) revert CustomFlowImplZeroAddress();
        if (newImplementation.code.length == 0) revert CustomFlowImplNotContract(newImplementation);
        address old = customFlowImpl;
        customFlowImpl = newImplementation;
        emit CustomFlowImplUpdated(old, newImplementation);
    }

    /// @notice Update the shared `SingleAllocatorStrategy` implementation used for new deployments
    /// @param newImplementation Address of the new `SingleAllocatorStrategy` implementation
    function setSingleAllocatorStrategyImpl(address newImplementation) external onlyOwner {
        if (newImplementation == address(0)) revert StrategyImplZeroAddress();
        if (newImplementation.code.length == 0) revert StrategyImplNotContract(newImplementation);
        address old = singleAllocatorStrategyImpl;
        singleAllocatorStrategyImpl = newImplementation;
        emit SingleAllocatorStrategyImplUpdated(old, newImplementation);
    }

    /// @notice Update the fixed connect pool admin address applied to new flows
    /// @param newConnectPoolAdmin New connect pool admin
    function setConnectPoolAdmin(address newConnectPoolAdmin) external onlyOwner {
        if (newConnectPoolAdmin == address(0)) revert ConnectPoolAdminZeroAddress();
        address old = connectPoolAdmin;
        connectPoolAdmin = newConnectPoolAdmin;
        emit ConnectPoolAdminUpdated(old, newConnectPoolAdmin);
    }

    /// @notice Update the fixed manager reward pool address applied to new flows
    /// @param newManagerRewardPool New manager reward pool address
    function setManagerRewardPool(address newManagerRewardPool) external onlyOwner {
        if (newManagerRewardPool == address(0)) revert ManagerRewardPoolZeroAddress();
        address old = managerRewardPool;
        managerRewardPool = newManagerRewardPool;
        emit ManagerRewardPoolUpdated(old, newManagerRewardPool);
    }

    /// @notice Update the fixed manager reward pool flow rate percent (PPM scale)
    /// @param newManagerRewardPoolFlowRatePercent New percent in PPM (<= 1e6)
    function setManagerRewardFlowRatePercent(uint32 newManagerRewardPoolFlowRatePercent) external onlyOwner {
        if (newManagerRewardPoolFlowRatePercent > 1_000_000) revert InvalidManagerRewardPercent();
        uint32 old = managerRewardPoolFlowRatePercent;
        managerRewardPoolFlowRatePercent = newManagerRewardPoolFlowRatePercent;
        emit ManagerRewardFlowRatePercentUpdated(old, newManagerRewardPoolFlowRatePercent);
    }

    /// @notice Update the fixed sanctions oracle applied to new flows
    /// @param newSanctionsOracle New sanctions oracle contract
    function setSanctionsOracle(IChainalysisSanctionsList newSanctionsOracle) external onlyOwner {
        if (address(newSanctionsOracle) == address(0)) revert SanctionsOracleZeroAddress();
        if (address(newSanctionsOracle).code.length == 0)
            revert SanctionsOracleNotContract(address(newSanctionsOracle));
        address old = address(sanctionsOracle);
        sanctionsOracle = newSanctionsOracle;
        emit SanctionsOracleUpdated(old, address(newSanctionsOracle));
    }

    // ---- UUPS ----
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
