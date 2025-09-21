// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FlowStorageV1 } from "./storage/FlowStorage.sol";
import { IFlow } from "./interfaces/IFlow.sol";
import { IAllocationStrategy } from "./interfaces/IAllocationStrategy.sol";
import { FlowRecipients } from "./library/FlowRecipients.sol";
import { FlowAllocations } from "./library/FlowAllocations.sol";
import { FlowPools } from "./library/FlowPools.sol";
import { FlowRates } from "./library/FlowRates.sol";
import { FlowInitialization } from "./library/FlowInitialization.sol";

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ISuperToken, ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

import { IChainalysisSanctionsList } from "./interfaces/external/chainalysis/IChainalysisSanctionsList.sol";

abstract contract Flow is IFlow, UUPSUpgradeable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable, FlowStorageV1 {
    using SuperTokenV1Library for ISuperToken;
    using FlowRecipients for Storage;
    using FlowAllocations for Storage;
    using FlowRates for Storage;
    using FlowInitialization for Storage;
    using FlowPools for Storage;
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Initializes the Flow contract
     * @param _initialOwner The address of the initial owner
     * @param _superToken The address of the SuperToken to be used for the pool
     * @param _manager The address of the flow manager
     * @param _managerRewardPool The address of the manager reward pool
     * @param _parent The address of the parent flow contract (optional)
     * @param _connectPoolAdmin The address of the admin that can connect the pool
     * @param _flowParams The parameters for the flow contract
     * @param _metadata The metadata for the flow contract
     * @param _sanctionsOracle The address of the sanctions oracle
     * @param _strategies The allocation strategies to use.
     */
    function __Flow_init(
        address _initialOwner,
        address _superToken,
        address _flowImpl,
        address _manager,
        address _managerRewardPool,
        address _parent,
        address _connectPoolAdmin,
        FlowParams memory _flowParams,
        RecipientMetadata memory _metadata,
        IChainalysisSanctionsList _sanctionsOracle,
        IAllocationStrategy[] calldata _strategies
    ) internal onlyInitializing {
        fs.checkAndSetInitializationParams(
            _initialOwner,
            _flowImpl,
            _manager,
            _superToken,
            _managerRewardPool,
            _parent,
            address(this),
            _connectPoolAdmin,
            _flowParams,
            _metadata,
            _sanctionsOracle,
            _strategies
        );

        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _transferOwnership(_initialOwner);

        emit FlowInitialized(
            _initialOwner,
            _superToken,
            _flowImpl,
            _manager,
            _managerRewardPool,
            _parent,
            address(fs.baselinePool),
            address(fs.bonusPool),
            fs.baselinePoolFlowRatePercent,
            fs.managerRewardPoolFlowRatePercent,
            _strategies
        );
        for (uint256 i = 0; i < _strategies.length; i++) {
            emit AllocationStrategyRegistered(address(this), address(_strategies[i]), _strategies[i].strategyKey());
        }

        emit SanctionsOracleSet(address(_sanctionsOracle));
    }

    // ========= Option C core: commitment + witness, delta updates (no per-recipient storage writes) =========
    /**
     * @dev Applies allocation deltas for a single (strategy, allocationKey).
     * - Verifies the witness against the stored commitment (order-independent).
     * - On first use for a key, migrates from legacy storage,
     * - using exact legacy memberUnits for deltas (no rounding drift).
     * - Computes new per-recipient units from strategy.currentWeight(key) and new BPS.
     * - Updates pool units by delta (one call per touched recipient).
     * - Updates totalActiveAllocationWeight: subtract previous **sum-of-floors**, add **new strategy weight**.
     * - Stores the new commitment.
     */
    function _applyAllocationWithWitness(
        address strategy,
        uint256 allocationKey,
        bytes32[] memory prevRecipientIds,
        uint32[] memory prevBps,
        uint256 prevWeight, // weight used to compute previous units (from last commit)
        bytes32[] calldata newRecipientIds,
        uint32[] calldata newBps
    ) internal returns (uint256 childFlowsToUpdate, bool shouldUpdateFlowRate) {
        (childFlowsToUpdate, shouldUpdateFlowRate) = fs.applyAllocationWithWitness(
            _childFlows,
            _childFlowsToUpdateFlowRate,
            strategy,
            allocationKey,
            prevRecipientIds,
            prevBps,
            prevWeight,
            newRecipientIds,
            newBps
        );
    }

    /**
     * @notice Modifier to restrict access to only the manager
     */
    modifier onlyManager() {
        if (msg.sender != fs.manager) revert SENDER_NOT_MANAGER();
        _;
    }

    /**
     * @notice Modifier to restrict access to only the owner or the manager
     */
    modifier onlyOwnerOrManager() {
        if (msg.sender != owner() && msg.sender != fs.manager) revert NOT_OWNER_OR_MANAGER();
        _;
    }

    /**
     * @notice Modifier to restrict access to only the owner or the parent
     */
    modifier onlyOwnerOrParent() {
        if (msg.sender != owner() && msg.sender != fs.parent) revert NOT_OWNER_OR_PARENT();
        _;
    }

    /**
     * @notice Revert if `sanctionsOracle` is set and `account` is sanctioned.
     */
    function _requireNotSanctioned(address account) internal view {
        IChainalysisSanctionsList sanctionsOracle_ = fs.sanctionsOracle;
        if (address(sanctionsOracle_) != address(0)) {
            if (sanctionsOracle_.isSanctioned(account)) revert SANCTIONED_RECIPIENT();
        }
    }

    /**
     * @notice Adds an address to the list of approved recipients
     * @param _recipientId The ID of the recipient. Must be unique and not already in use.
     * @param _recipient The address to be added as an approved recipient
     * @param _metadata The metadata of the recipient
     * @return bytes32 The recipientId of the newly created recipient
     * @return address The address of the newly created recipient
     */
    function addRecipient(
        bytes32 _recipientId,
        address _recipient,
        RecipientMetadata memory _metadata
    ) external onlyManager nonReentrant returns (bytes32, address) {
        (, address recipientAddress) = fs.addRecipient(_recipientId, _recipient, _metadata);

        // check if recipient is sanctioned
        _requireNotSanctioned(_recipient);

        emit RecipientCreated(_recipientId, fs.recipients[_recipientId], msg.sender);

        // need to do this here because we just added new member units
        _setChildrenAsNeedingUpdates(recipientAddress);

        fs.updateBaselineMemberUnits(recipientAddress, BASELINE_MEMBER_UNITS);
        // 10 units for each recipient in case there are no allocations yet, everyone will split the bonus salary
        fs.updateBonusMemberUnits(recipientAddress, 10);

        _workOnChildFlowsToUpdate(10);

        return (_recipientId, recipientAddress);
    }

    /**
     * @notice Adds a new Flow contract as a recipient
     * @dev This function creates a new Flow contract and adds it as a recipient
     * @param _recipientId The ID of the recipient. Must be unique and not already in use.
     * @param _metadata The metadata of the recipient
     * @param _flowManager The address of the flow manager for the new contract
     * @param _managerRewardPool The address of the manager reward pool for the new contract
     * @param _strategies The allocation strategies to use.
     * @return bytes32 The recipientId of the newly created Flow contract
     * @return address The address of the newly created Flow contract
     * @dev Only callable by the manager of the contract
     * @dev Emits a RecipientCreated event if the recipient is successfully added
     */
    function addFlowRecipient(
        bytes32 _recipientId,
        RecipientMetadata calldata _metadata,
        address _flowManager,
        address _managerRewardPool,
        IAllocationStrategy[] calldata _strategies
    ) external onlyManager nonReentrant returns (bytes32, address) {
        FlowRecipients.validateFlowRecipient(_metadata, _flowManager);

        address recipient = _deployFlowRecipient(_metadata, _flowManager, _managerRewardPool, _strategies);

        fs.addFlowRecipient(_recipientId, recipient, _metadata);
        _childFlows.add(recipient);
        _maybeTakeFlowRateSnapshot(recipient);

        emit FlowRecipientCreated(
            _recipientId,
            recipient,
            address(IFlow(recipient).baselinePool()),
            address(IFlow(recipient).bonusPool()),
            IFlow(recipient).managerRewardPoolFlowRatePercent(),
            IFlow(recipient).baselinePoolFlowRatePercent()
        );
        emit RecipientCreated(_recipientId, fs.recipients[_recipientId], msg.sender);

        // need to do this here because we just added new member units
        _setChildrenAsNeedingUpdates(recipient);

        // do this after so member units based indexer can work
        // for indexer, need to connect tcr item in database to recipient BEFORE handling member units
        // 10 bonus units for each recipient in case there are no allocations yet, everyone will split the bonus salary
        fs.connectAndInitializeFlowRecipient(recipient, BASELINE_MEMBER_UNITS, 10);

        // set the flow rate for the child contract
        _setChildFlowRate(recipient);

        _workOnChildFlowsToUpdate(10);

        return (_recipientId, recipient);
    }

    /**
     * @notice Sets all the child flow rates
     * @param ignoredAddress The address of the child flow to ignore. Useful when adding a new flow recipient
     * @dev Called when total member units change (new flow added, flow removed, new vote added)
     */
    function _setChildrenAsNeedingUpdates(address ignoredAddress) internal {
        fs.setChildrenAsNeedingUpdates(_childFlows, _childFlowsToUpdateFlowRate, ignoredAddress);
    }

    /**
     * @notice Internal function to be called after allocations are set
     * @param recipientIds - the recipientIds that were allocated for
     * @param childFlowsToUpdate - the number of child flows to update
     * @param shouldUpdateFlowRate - whether to update the flow rate
     * Useful for saving gas when there are no new allocations. If there are new member units being added however,
     * we want to update all child flow rates to ensure that the correct flow rates are set
     */
    function _afterAllocationSet(
        bytes32[] memory recipientIds,
        uint256 childFlowsToUpdate,
        bool shouldUpdateFlowRate
    ) internal {
        if (shouldUpdateFlowRate) {
            _setFlowRate(getTotalFlowRate());
        } else {
            // set the flow rate for the child contracts that were voted for
            for (uint256 i = 0; i < recipientIds.length; i++) {
                bytes32 recipientId = recipientIds[i];
                address recipientAddress = fs.recipients[recipientId].recipient;
                if (!_childFlows.contains(recipientAddress) || fs.recipients[recipientId].removed) continue;
                _setChildFlowRate(recipientAddress);
            }

            _workOnChildFlowsToUpdate(childFlowsToUpdate);
        }
    }

    /**
     * @notice Internal function to work on the child flows that need their flow rate updated
     * @param updateCount The number of child flows to update
     */
    function _workOnChildFlowsToUpdate(uint256 updateCount) internal {
        fs.workOnChildFlowsToUpdate(_childFlowsToUpdateFlowRate, _childFlows, address(this), updateCount);
    }

    /**
     * @notice Public function to work on the child flows that need their flow rate updated
     * @param updateCount The number of child flows to update
     */
    function workOnChildFlowsToUpdate(uint256 updateCount) external nonReentrant {
        _workOnChildFlowsToUpdate(updateCount);
    }

    /**
     * @notice Public function to get the number of child flows that need their flow rate updated
     * @return The number of child flows that need their flow rate updated
     */
    function childFlowRatesOutOfSync() external view returns (uint256) {
        return _childFlowsToUpdateFlowRate.length();
    }

    /**
     * @notice Virtual function to calculate the total vote weight of all tokens used for voting
     * @dev This function can be overridden in derived contracts to implement custom logic
     * @return uint256 The total vote weight of all tokens used for voting
     */
    function totalAllocationWeight() public view virtual returns (uint256) {}

    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function is virtual to allow for different deployment strategies in derived contracts
     * @param _metadata The metadata of the recipient
     * @param _flowManager The address of the flow manager for the new contract
     * @param _managerRewardPool The address of the manager reward pool for the new contract
     * @param _strategies The allocation strategies to use.
     * @return address The address of the newly created Flow contract
     */
    function _deployFlowRecipient(
        RecipientMetadata calldata _metadata,
        address _flowManager,
        address _managerRewardPool,
        IAllocationStrategy[] calldata _strategies
    ) internal virtual returns (address);

    /**
     * @notice Removes a recipient for receiving funds
     * @param recipientId The ID of the recipient to be approved
     * @dev Only callable by the manager of the contract
     * @dev Emits a RecipientRemoved event if the recipient is successfully removed
     */
    function removeRecipient(bytes32 recipientId) external onlyManager nonReentrant {
        (address recipientAddress, RecipientType recipientType) = fs.removeRecipient(
            _childFlows,
            _childFlowsToUpdateFlowRate,
            recipientId
        );

        if (recipientType == RecipientType.FlowContract) {
            fs.clearFlowRateSnapshot(recipientAddress);
        }

        // snapshot the surviving children *before* units change
        _setChildrenAsNeedingUpdates(address(0));

        // Be careful changing event ordering here, indexer expects to delete recipient
        // when memberUnits is set to 0
        emit RecipientRemoved(recipientAddress, recipientId);

        fs.removeFromPools(recipientAddress);
        _setFlowRate(getTotalFlowRate());
    }

    /**
     * @notice Sets the flow rate for a child Flow contract
     * @param childAddress The address of the child Flow contract
     */
    function _setChildFlowRate(address childAddress) internal {
        fs.setChildFlowRate(childAddress, address(this), _childFlows, _childFlowsToUpdateFlowRate);
    }

    /**
     * @notice Takes a snapshot of the child flow rate
     * @param child The address of the child flow contract
     */
    function _maybeTakeFlowRateSnapshot(address child) internal {
        fs.maybeTakeFlowRateSnapshot(_childFlows, child);
    }

    /**
     * @notice Connects this contract to a Superfluid pool
     * @param poolAddress The address of the Superfluid pool to connect to
     * @dev Only callable by the owner or parent of the contract
     * @dev Emits a PoolConnected event upon successful connection
     */
    function connectPool(ISuperfluidPool poolAddress) external nonReentrant {
        if (address(poolAddress) == address(0)) revert ADDRESS_ZERO();
        if (msg.sender != owner() && msg.sender != fs.parent && msg.sender != fs.connectPoolAdmin)
            revert NOT_ALLOWED_TO_CONNECT_POOL();

        bool success = fs.superToken.connectPool(poolAddress);
        if (!success) revert POOL_CONNECTION_FAILED();
    }

    /**
     * @notice Sets the flow rate for the Superfluid pool
     * @param _flowRate The new flow rate to be set
     * @dev Only callable by the owner or parent of the contract
     */
    function setFlowRate(int96 _flowRate) external onlyOwnerOrParent nonReentrant {
        _setFlowRate(_flowRate);
    }

    /**
     * @notice Raise the outflow to `desiredRate`, pulling only the incremental buffer.
     * @param amount  New outflow to add to the current flow rate
     */
    function increaseFlowRate(int96 amount) external nonReentrant {
        if (isFlowRateTooHigh()) return;

        (uint256 toPull, int96 oldRate, int96 newRate, int96 delta) = fs.increaseFlowRate(
            address(this),
            amount,
            getBufferMultiplier()
        );

        if (delta <= 0) return;

        if (toPull > 0) {
            fs.superToken.transferFrom(msg.sender, address(this), toPull);
        }

        _setFlowRate(newRate);

        emit FlowRateIncreased(msg.sender, oldRate, newRate, toPull);
    }

    /**
     * @notice Gets the buffer multiplier
     * @dev This function is used to get the buffer multiplier
     * @return The buffer multiplier
     */
    function getBufferMultiplier() public view returns (uint256) {
        return fs.getBufferMultiplier(_childFlows);
    }

    /**
     * @notice Gets the required buffer amount for a given flow rate
     * @param amount The flow rate to get the required buffer amount for
     * @return The required buffer amount
     */
    function getRequiredBufferAmount(int96 amount) public view returns (uint256) {
        return fs.getRequiredBufferAmount(amount, getBufferMultiplier());
    }

    /**
     * @notice Balances the flow rate if it is too high
     * @dev This function is used to balance the flow rate to the maximum flow rate
     * @dev Emits a FlowRateDecreased event if the flow rate is successfully decreased
     */
    function decreaseFlowRate() external nonReentrant {
        int96 oldRate = getActualFlowRate();
        int96 newRate = getMaxSafeFlowRate();

        // if the flow rate is already below the maximum flow rate, do nothing
        if (newRate >= oldRate) return;

        _setFlowRate(newRate);

        emit FlowRateDecreased(msg.sender, oldRate, newRate);
    }

    /**
     * @notice Sets the address of the grants implementation contract
     * @param _flowImpl The new address of the grants implementation contract
     */
    function setFlowImpl(address _flowImpl) external onlyOwner nonReentrant {
        if (_flowImpl == address(0)) revert ADDRESS_ZERO();

        fs.flowImpl = _flowImpl;
        emit FlowImplementationSet(_flowImpl);
    }

    /**
     * @notice Sets a new manager for the Flow contract
     * @param _newManager The address of the new manager
     * @dev Only callable by the current owner or manager
     */
    function setManager(address _newManager) external onlyOwnerOrManager nonReentrant {
        if (_newManager == address(0)) revert ADDRESS_ZERO();

        address oldManager = fs.manager;
        fs.manager = _newManager;
        emit ManagerUpdated(oldManager, _newManager);
    }

    /**
     * @notice Sets the address of the admin that can connect the pool
     * @param _connectPoolAdmin The address of the admin that can connect the pool
     * @dev Only callable by the current owner
     */
    function setConnectPoolAdmin(address _connectPoolAdmin) external onlyOwner nonReentrant {
        if (_connectPoolAdmin == address(0)) revert ADDRESS_ZERO();

        address oldConnectPoolAdmin = fs.connectPoolAdmin;
        fs.connectPoolAdmin = _connectPoolAdmin;
        emit ConnectPoolAdminUpdated(oldConnectPoolAdmin, _connectPoolAdmin);
    }

    /**
     * @notice Sets a new manager reward pool for the Flow contract
     * @param _newManagerRewardPool The address of the new manager reward pool
     * @dev Only callable by the current owner or manager
     * @dev Emits a ManagerRewardPoolUpdated event with the old and new manager reward pool addresses
     */
    function setManagerRewardPool(address _newManagerRewardPool) external onlyOwnerOrManager nonReentrant {
        if (_newManagerRewardPool == address(0)) revert ADDRESS_ZERO();

        address oldManagerRewardPool = fs.managerRewardPool;
        fs.managerRewardPool = _newManagerRewardPool;
        emit ManagerRewardPoolUpdated(oldManagerRewardPool, _newManagerRewardPool);
    }

    /**
     * @notice Returns the SuperToken address
     * @return The address of the SuperToken
     */
    function getSuperToken() external view returns (address) {
        return address(fs.superToken);
    }

    /**
     * @notice Sets the flow to the manager reward pool
     * @param _newManagerRewardFlowRate The new flow rate to the manager reward pool
     */
    function _setFlowToManagerRewardPool(int96 _newManagerRewardFlowRate) internal {
        // some flows initially don't have a manager reward pool, so we don't need to set a flow to it
        if (fs.managerRewardPool == address(0)) return;

        fs.setFlowToManagerRewardPool(address(this), getManagerRewardPoolFlowRate(), _newManagerRewardFlowRate);
    }

    /**
     * @notice Internal function to set the flow rate for the Superfluid pools and the manager reward pool
     * @param _flowRate The new flow rate to be set
     */
    function _setFlowRate(int96 _flowRate) internal {
        fs.ensureMinimumPoolUnits(address(this));

        if (_flowRate < 0) revert FLOW_RATE_NEGATIVE();

        fs.cachedFlowRate = _flowRate;

        (int96 baselineFlowRate, int96 bonusFlowRate, int96 managerRewardFlowRate) = fs.calculateFlowRates(
            _flowRate,
            totalAllocationWeight()
        );

        _setFlowToManagerRewardPool(managerRewardFlowRate);

        _setChildrenAsNeedingUpdates(address(0));

        fs.distributeFlowToPools(address(this), bonusFlowRate, baselineFlowRate);

        // changing flow rate means we need to update all child flow rates
        _workOnChildFlowsToUpdate(10);
    }

    /**
     * @notice Sets the baseline flow rate percentage
     * @param _baselineFlowRatePercent The new baseline flow rate percentage
     * @dev Only callable by the owner or manager of the contract
     * @dev Emits a BaselineFlowRatePercentUpdated event with the old and new percentages
     */
    function _setBaselineFlowRatePercent(uint32 _baselineFlowRatePercent) internal {
        if (_baselineFlowRatePercent > fs.PERCENTAGE_SCALE) revert INVALID_PERCENTAGE();
        if (_baselineFlowRatePercent + fs.managerRewardPoolFlowRatePercent > fs.PERCENTAGE_SCALE)
            revert INVALID_PERCENTAGE();

        emit BaselineFlowRatePercentUpdated(fs.baselinePoolFlowRatePercent, _baselineFlowRatePercent);

        fs.baselinePoolFlowRatePercent = _baselineFlowRatePercent;

        // Update flow rates to reflect the new percentage
        _setFlowRate(getTotalFlowRate());
    }

    /**
     * @dev Only callable by the owner or manager of the contract
     */
    function setBaselineFlowRatePercent(uint32 _baselineFlowRatePercent) external onlyOwnerOrManager nonReentrant {
        _setBaselineFlowRatePercent(_baselineFlowRatePercent);
    }

    /**
     * @notice Sets the flow buffer multiplier
     * @param _bufferMultiplier The new flow buffer multiplier
     * @dev Only callable by the owner or manager of the contract
     */
    function setDefaultBufferMultiplier(uint256 _bufferMultiplier) external onlyOwnerOrManager {
        uint256 oldBufferMultiplier = fs.setDefaultBufferMultiplier(_bufferMultiplier);
        emit BufferMultiplierUpdated(oldBufferMultiplier, _bufferMultiplier);
    }

    /**
     * @notice Sets the bonus pool quorum parameters
     * @param _quorumBps The new quorum percentage (in basis points, scaled by PERCENTAGE_SCALE).
     * Once reached, the bonus pool will be scaled up to the maximum available flow rate.
     * (total - baseline - manager reward)
     * Leftover flow rate when quorum is not reached will be added to the baseline pool.
     * @dev Only callable by the owner or manager of the contract
     */
    function _setBonusPoolQuorum(uint32 _quorumBps) internal {
        if (_quorumBps > fs.PERCENTAGE_SCALE) revert INVALID_PERCENTAGE();

        emit BonusPoolQuorumUpdated(fs.bonusPoolQuorumBps, _quorumBps);

        fs.bonusPoolQuorumBps = _quorumBps;

        _setFlowRate(getTotalFlowRate());
    }

    /**
     * @dev Only callable by the owner or manager of the contract
     */
    function setBonusPoolQuorum(uint32 _quorumBps) external onlyOwnerOrManager nonReentrant {
        _setBonusPoolQuorum(_quorumBps);
    }

    /**
     * @notice Sets the manager reward flow rate percentage
     * @param _managerRewardFlowRatePercent The new manager reward flow rate percentage
     * @dev Only callable by the owner or manager of the contract
     * @dev Emits a ManagerRewardFlowRatePercentUpdated event with the old and new percentages
     */
    function setManagerRewardFlowRatePercent(uint32 _managerRewardFlowRatePercent) external onlyOwner nonReentrant {
        if (_managerRewardFlowRatePercent > fs.PERCENTAGE_SCALE) revert INVALID_PERCENTAGE();

        emit ManagerRewardFlowRatePercentUpdated(fs.managerRewardPoolFlowRatePercent, _managerRewardFlowRatePercent);

        fs.managerRewardPoolFlowRatePercent = _managerRewardFlowRatePercent;

        // Update flow rates to reflect the new percentage
        _setFlowRate(getTotalFlowRate());
    }

    /**
     * @notice Let's the owner set the metadata for the flow
     * @param metadata The metadata of the flow
     */
    function setMetadata(RecipientMetadata memory metadata) external onlyOwnerOrManager {
        FlowRecipients.validateMetadata(metadata);
        fs.metadata = metadata;
        emit MetadataSet(metadata);
    }

    /**
     * @notice Sets the description for the flow
     * @param description The new description for the flow
     */
    function setDescription(string calldata description) external onlyOwnerOrManager {
        fs.metadata.description = description;
        emit MetadataSet(fs.metadata);
    }

    /**
     * @notice Set the sanctions oracle address.
     * @dev Only callable by the owner.
     */
    function setSanctionsOracle(address newSanctionsOracle) public onlyOwnerOrParent {
        fs.sanctionsOracle = IChainalysisSanctionsList(newSanctionsOracle);

        emit SanctionsOracleSet(newSanctionsOracle);
    }

    /**
     * @notice Resets the flow rate to the current total flow rate
     * @dev This function is open to all and can be called to ensure the flow rate is up-to-date
     * @dev It calls the internal _setFlowRate function with the current total flow rate
     * @dev Useful in case parent didn't have enough to cover the buffer amount and start
     * the flow for this contract (assuming this is a child flow)
     */
    function resetFlowRate() external nonReentrant {
        _setFlowRate(getTotalFlowRate());
    }

    /**
     * @notice Retrieves the flow rate for a specific member in the pool
     * @param memberAddr The address of the member
     * @return flowRate The flow rate for the member
     */
    function getMemberTotalFlowRate(address memberAddr) public view returns (int96) {
        return fs.getMemberTotalFlowRate(memberAddr);
    }

    /**
     * @notice Retrieves the total member units for a specific member across both pools
     * @param memberAddr The address of the member
     * @return totalUnits The total units for the member
     */
    function getTotalMemberUnits(address memberAddr) public view returns (uint256) {
        return fs.getTotalMemberUnits(memberAddr);
    }

    /**
     * @notice Retrieves all child flow addresses
     * @return addresses An array of addresses representing all child flows
     */
    function getChildFlows() external view returns (address[] memory) {
        return _childFlows.values();
    }

    /**
     * @notice Retrieves the total amount received by a specific member in the pool
     * @param memberAddr The address of the member
     * @return totalAmountReceived The total amount received by the member
     */
    function getTotalReceivedByMember(address memberAddr) external view returns (uint256) {
        return fs.getTotalAmountReceivedByMember(memberAddr);
    }

    /**
     * @return totalFlowRate The total flow rate of the pools and the manager reward pool
     */
    function getTotalFlowRate() public view returns (int96) {
        return fs.cachedFlowRate;
    }

    /**
     * @notice Retrieves the actual flow rate for the contract
     * @return int96 The actual flow rate
     */
    function getActualFlowRate() public view returns (int96) {
        return fs.getActualFlowRate(address(this));
    }

    /**
     * @notice Gets the net flow rate for the contract
     * @dev This function is used to get the net flow rate for the contract
     * @return The net flow rate
     */
    function getNetFlowRate() public view returns (int96) {
        return fs.getNetFlowRate(address(this));
    }

    /**
     * @notice Read-only commitment (hash) for an allocation key
     * @dev commit = keccak256(abi.encode(canonical(weight, recipientIds, percentAllocations)))
     * Canonicalized by recipientId asc.
     */
    function getAllocationCommitment(address strategy, uint256 allocationKey) external view returns (bytes32) {
        return fs.allocCommit[strategy][allocationKey];
    }

    /**
     * @notice Returns the maximum safe outflow rate allowed by the contract.
     * @dev Calculates the highest outflow rate permitted, capped as a percentage of the current incoming Superfluid stream.
     *      This ensures the contract never streams out more than a set fraction of what it receives.
     * @return The maximum safe flow rate (int96) that can be set without exceeding the cap.
     */
    function getMaxSafeFlowRate() public view returns (int96) {
        return fs.getMaxSafeFlowRate(address(this));
    }

    /**
     * @notice Checks if the flow rate is too high
     * @dev This function is used to check if incoming flow rate is less than the outgoing flow rate
     * @return True if the flow rate is too high, false otherwise
     */
    function isFlowRateTooHigh() public view returns (bool) {
        return fs.isFlowRateTooHigh(address(this));
    }

    /**
     * @notice Retrieves a recipient by their ID
     * @param recipientId The ID of the recipient to retrieve
     * @return recipient The FlowRecipient struct containing the recipient's information
     */
    function getRecipientById(bytes32 recipientId) external view returns (FlowRecipient memory recipient) {
        recipient = fs.recipients[recipientId];
        if (recipient.recipient == address(0)) revert RECIPIENT_NOT_FOUND();
        return recipient;
    }

    /**
     * @notice Checks if a recipient exists
     * @param recipient The address of the recipient to check
     * @return exists True if the recipient exists, false otherwise
     */
    function recipientExists(address recipient) public view returns (bool) {
        return fs.recipientExists[recipient];
    }

    /**
     * @notice Retrieves the baseline pool flow rate percentage
     * @return uint256 The baseline pool flow rate percentage
     */
    function baselinePoolFlowRatePercent() external view returns (uint32) {
        return fs.baselinePoolFlowRatePercent;
    }

    /**
     * @notice Retrieves the metadata for this Flow contract
     * @return RecipientMetadata The metadata struct containing title, description, image, tagline, and url
     */
    function flowMetadata() external view returns (RecipientMetadata memory) {
        return fs.metadata;
    }

    /**
     * @notice Gets the count of active recipients
     * @return count The number of active recipients
     */
    function activeRecipientCount() public view returns (uint256) {
        return fs.activeRecipientCount;
    }

    /**
     * @notice Retrieves the baseline pool
     * @return ISuperfluidPool The baseline pool
     */
    function baselinePool() external view returns (ISuperfluidPool) {
        return fs.baselinePool;
    }

    /**
     * @notice Retrieves the bonus pool
     * @return ISuperfluidPool The bonus pool
     */
    function bonusPool() external view returns (ISuperfluidPool) {
        return fs.bonusPool;
    }

    /**
     * @notice Retrieves the SuperToken used for the flow
     * @return ISuperToken The SuperToken instance
     */
    function superToken() external view returns (ISuperToken) {
        return fs.superToken;
    }

    /**
     * @notice Retrieves the flow implementation contract address
     * @return address The address of the flow implementation contract
     */
    function flowImpl() external view returns (address) {
        return fs.flowImpl;
    }

    /**
     * @notice Retrieves the parent contract address
     * @return address The address of the parent contract
     */
    function parent() external view returns (address) {
        return fs.parent;
    }

    /**
     * @notice Retrieves the manager address
     * @return address The address of the manager
     */
    function manager() external view returns (address) {
        return fs.manager;
    }

    /**
     * @notice Retrieves the connect pool admin address
     * @return address The address of the connect pool admin
     */
    function connectPoolAdmin() external view returns (address) {
        return fs.connectPoolAdmin;
    }

    /**
     * @notice Retrieves the manager reward pool address
     * @return address The address of the manager reward pool
     */
    function managerRewardPool() external view returns (address) {
        return fs.managerRewardPool;
    }

    /**
     * @notice Retrieves the total active vote weight for quorum purposes
     * @return uint256 The total active vote weight
     */
    function totalActiveAllocationWeight() external view returns (uint256) {
        return fs.totalActiveAllocationWeight;
    }

    /**
     * @notice Retrieves the current flow rate to the manager reward pool
     * @return flowRate The current flow rate to the manager reward pool
     */
    function getManagerRewardPoolFlowRate() public view returns (int96) {
        return fs.getManagerRewardPoolFlowRate(address(this));
    }

    /**
     * @notice Retrieves the rewards pool flow rate percentage
     * @return uint256 The rewards pool flow rate percentage
     */
    function managerRewardPoolFlowRatePercent() external view returns (uint32) {
        return fs.managerRewardPoolFlowRatePercent;
    }

    /**
     * @notice Retrieves the claimable balance from both pools for a member address
     * @param member The address of the member to check the claimable balance for
     * @return claimable The claimable balance from both pools
     */
    function getClaimableBalance(address member) external view returns (uint256) {
        return fs.getClaimableBalance(member);
    }

    /**
     * @notice Retrieves the allocation strategies
     * @return IAllocationStrategy[] The allocation strategies
     */
    function strategies() external view returns (IAllocationStrategy[] memory) {
        return fs.strategies;
    }

    /**
     * @notice Retrieves the percentage scale
     * @return uint32 The percentage scale used for percentage calculations
     */
    function PERCENTAGE_SCALE() external view returns (uint32) {
        return fs.PERCENTAGE_SCALE;
    }

    /**
     * @notice Upgrades all child flows to a new implementation
     */
    function upgradeAllChildFlows() external onlyOwner nonReentrant {
        uint256 len = _childFlows.length();
        for (uint256 i; i < len; ++i) {
            address child = _childFlows.at(i);
            Flow(child).upgradeTo(fs.flowImpl);
        }
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param _newImpl The new implementation address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwnerOrParent {}
}
