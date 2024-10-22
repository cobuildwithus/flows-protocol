// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FlowStorageV1 } from "./storage/FlowStorageV1.sol";
import { IFlow } from "./interfaces/IFlow.sol";
import { IRewardPool } from "./interfaces/IRewardPool.sol";
import { FlowRecipients } from "./library/FlowRecipients.sol";
import { FlowVotes } from "./library/FlowVotes.sol";
import { FlowRates } from "./library/FlowRates.sol";
import { FlowInitialization } from "./library/FlowInitialization.sol";

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { ISuperToken, ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

abstract contract Flow is IFlow, UUPSUpgradeable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable, FlowStorageV1 {
    using SuperTokenV1Library for ISuperToken;
    using FlowRecipients for Storage;
    using FlowVotes for Storage;
    using FlowRates for Storage;
    using FlowInitialization for Storage;
    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @notice Initializes the Flow contract
     * @param _initialOwner The address of the initial owner
     * @param _superToken The address of the SuperToken to be used for the pool
     * @param _manager The address of the flow manager
     * @param _managerRewardPool The address of the manager reward pool
     * @param _parent The address of the parent flow contract (optional)
     * @param _flowParams The parameters for the flow contract
     * @param _metadata The metadata for the flow contract
     */
    function __Flow_init(
        address _initialOwner,
        address _superToken,
        address _flowImpl,
        address _manager,
        address _managerRewardPool,
        address _parent,
        FlowParams memory _flowParams,
        RecipientMetadata memory _metadata
    ) public {
        fs.checkAndSetInitializationParams(
            _initialOwner,
            _flowImpl,
            _manager,
            _superToken,
            _managerRewardPool,
            _parent,
            address(this),
            _flowParams,
            _metadata,
            PERCENTAGE_SCALE
        );

        __Ownable2Step_init();
        __ReentrancyGuard_init();

        _transferOwnership(_initialOwner);

        emit FlowInitialized(
            msg.sender,
            _superToken,
            _flowImpl,
            _manager,
            _managerRewardPool,
            _parent,
            address(fs.baselinePool),
            address(fs.bonusPool),
            fs.baselinePoolFlowRatePercent,
            fs.managerRewardPoolFlowRatePercent
        );
    }

    /**
     * @notice Cast a vote for a specific grant address.
     * @param recipientId The id of the grant recipient.
     * @param bps The basis points of the vote to be split with the recipient.
     * @param tokenId The tokenId owned by the voter.
     * @param totalWeight The voting power of the voter.
     * @param voter The address of the voter.
     * @dev Requires that the recipient is valid, and the weight is greater than the minimum vote weight.
     * Emits a VoteCast event upon successful execution.
     */
    function _vote(bytes32 recipientId, uint32 bps, uint256 tokenId, uint256 totalWeight, address voter) internal {
        // calculate new member units for recipient and create vote
        (uint128 memberUnits, address recipientAddress, ) = fs.createVote(
            recipientId,
            bps,
            tokenId,
            totalWeight,
            PERCENTAGE_SCALE,
            voter
        );

        // update member units
        _updateBonusMemberUnits(recipientAddress, memberUnits);

        // if recipient is a flow contract, set the flow rate for the child contract
        // note - we now do this post-voting to avoid redundant setFlowRate calls on children
        // in _afterVotesCast

        emit VoteCast(recipientId, tokenId, memberUnits, bps, totalWeight);
    }

    /**
     * @notice Clears out units from previous votes allocation for a specific tokenId.
     * @param tokenId The tokenId whose previous votes are to be cleared.
     * @dev This function resets the member units for all recipients that the tokenId has previously voted for.
     * It should be called before setting new votes to ensure accurate vote allocations.
     */
    function _clearPreviousVotes(uint256 tokenId) internal {
        VoteAllocation[] memory allocations = fs.votes[tokenId];
        for (uint256 i = 0; i < allocations.length; i++) {
            bytes32 recipientId = allocations[i].recipientId;

            // if recipient is removed, skip - don't want to update member units because they have been wiped to 0
            // fine because this vote will be deleted in the next step
            if (fs.recipients[recipientId].removed) continue;

            address recipientAddress = fs.recipients[recipientId].recipient;

            // Calculate the new units by subtracting the delta from the current units
            uint128 newUnits = fs.bonusPool.getUnits(recipientAddress) - allocations[i].memberUnits;

            emit VoteRemoved(recipientId, tokenId, newUnits);

            // Update the member units in the pool
            _updateBonusMemberUnits(recipientAddress, newUnits);

            /// @notice - Does not update member units for baseline pool
            /// voting is only for the bonus pool, to ensure all approved recipients get a baseline salary

            // after updating member units, set the flow rate for the child contract
            // if recipient is a flow contract, set the flow rate for the child contract
            // note - we now do this post-voting to avoid redundant setFlowRate calls on children
            // in _afterVotesCast
        }

        // Clear out the votes for the tokenId
        delete fs.votes[tokenId];
    }

    /**
     * @notice Cast a vote for a set of grant addresses.
     * @param tokenId The tokenId owned by the voter.
     * @param recipientIds The recipientIds of the grant recipients to vote for.
     * @param percentAllocations The basis points of the vote to be split with the recipients.
     */
    function _setVotesAllocationForTokenId(
        uint256 tokenId,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations,
        address voter
    ) internal {
        // update member units for previous votes
        _clearPreviousVotes(tokenId);

        // set new votes
        for (uint256 i = 0; i < recipientIds.length; i++) {
            _vote(recipientIds[i], percentAllocations[i], tokenId, fs.tokenVoteWeight, voter);
        }
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

        emit RecipientCreated(_recipientId, fs.recipients[_recipientId], msg.sender);

        _updateBaselineMemberUnits(recipientAddress, BASELINE_MEMBER_UNITS);
        // 10 units for each recipient in case there are no votes yet, everyone will split the bonus salary
        _updateBonusMemberUnits(recipientAddress, 10);

        return (_recipientId, recipientAddress);
    }

    /**
     * @notice Adds a new Flow contract as a recipient
     * @dev This function creates a new Flow contract and adds it as a recipient
     * @param _recipientId The ID of the recipient. Must be unique and not already in use.
     * @param _metadata The metadata of the recipient
     * @param _flowManager The address of the flow manager for the new contract
     * @param _managerRewardPool The address of the manager reward pool for the new contract
     * @return bytes32 The recipientId of the newly created Flow contract
     * @return address The address of the newly created Flow contract
     * @dev Only callable by the manager of the contract
     * @dev Emits a RecipientCreated event if the recipient is successfully added
     */
    function addFlowRecipient(
        bytes32 _recipientId,
        RecipientMetadata calldata _metadata,
        address _flowManager,
        address _managerRewardPool
    ) external onlyManager returns (bytes32, address) {
        FlowRecipients.validateFlowRecipient(_metadata, _flowManager);

        address recipient = _deployFlowRecipient(_metadata, _flowManager, _managerRewardPool);

        fs.addFlowRecipient(_recipientId, recipient, _metadata);
        _childFlows.add(recipient);

        emit FlowRecipientCreated(
            _recipientId,
            recipient,
            address(IFlow(recipient).baselinePool()),
            address(IFlow(recipient).bonusPool()),
            IFlow(recipient).managerRewardPoolFlowRatePercent(),
            IFlow(recipient).baselinePoolFlowRatePercent()
        );
        emit RecipientCreated(_recipientId, fs.recipients[_recipientId], msg.sender);

        // do this after so member units based indexer can work
        // for indexer, need to connect tcr item in database to recipient BEFORE handling member units
        _connectAndInitializeFlowRecipient(recipient);

        // set the flow rate for the child contract
        _setChildFlowRate(recipient);

        // need to do this here because we just added new member units
        _setCappedChildFlowRates(recipient);

        return (_recipientId, recipient);
    }

    /**
     * @notice Sets all the child flow rates
     * @param ignoredAddress The address of the child flow to ignore. Useful when adding a new flow recipient
     * @dev Called when total member units change (new flow added, flow removed, new vote added)
     * @dev This function will run out of gas eventually, so we cap it at 10
     * and expect a worker to call setChildFlowRates with the remaining child flows
     */
    function _setCappedChildFlowRates(address ignoredAddress) internal {
        uint256 cap = 10;

        // warning - values() copies entire array into memory, could run out of gas for huge arrays
        // must keep child flows below ~500 per o1 estimates
        address[] memory childFlows = _childFlows.values();
        address[] memory childrenToUpdateInWorker = new address[](
            cap > _childFlows.length() ? 0 : _childFlows.length() - cap
        );
        for (uint256 i = 0; i < childFlows.length; i++) {
            if (childFlows[i] == ignoredAddress) continue;

            if (i < cap) {
                _setChildFlowRate(childFlows[i]);
            } else {
                childrenToUpdateInWorker[i - cap] = childFlows[i];
            }
        }

        if (childrenToUpdateInWorker.length > 0) {
            emit ChildFlowRatesToUpdate(childrenToUpdateInWorker);
        }
    }

    /**
     * @notice Sets the flow rate for a specific child Flow contract
     * @param childFlows The addresses of the child Flow contracts
     * @dev This function is public to allow external calls, but it's protected by the onlyManager modifier
     */
    function setChildFlowRates(address[] memory childFlows) external nonReentrant {
        for (uint256 i = 0; i < childFlows.length; i++) {
            _setChildFlowRate(childFlows[i]);
        }
    }

    /**
     * @notice Internal function to be called after votes are cast
     * @param recipientIds - the recipientIds that were voted for
     * Useful for saving gas when there are no new votes. If there are new member units being added however,
     * we want to update all child flow rates to ensure that the correct flow rates are set
     */
    function _afterVotesCast(bytes32[] memory recipientIds) internal {
        // set the flow rate for the child contracts that were voted for
        for (uint256 i = 0; i < recipientIds.length; i++) {
            bytes32 recipientId = recipientIds[i];
            address recipientAddress = fs.recipients[recipientId].recipient;
            if (!_childFlows.contains(recipientAddress) || fs.recipients[recipientId].removed) continue;
            _setChildFlowRate(recipientAddress);
        }
    }

    /**
     * @notice Connects a new Flow contract to both pools and initializes its member units
     * @param recipient The address of the new Flow contract
     */
    function _connectAndInitializeFlowRecipient(address recipient) internal {
        // Connect the new child contract to both pools
        Flow(recipient).connectPool(fs.bonusPool);
        Flow(recipient).connectPool(fs.baselinePool);

        // Initialize member units
        _updateBaselineMemberUnits(recipient, BASELINE_MEMBER_UNITS);
        // 10 units for each recipient in case there are no votes yet, everyone will split the bonus salary
        _updateBonusMemberUnits(recipient, 10);
    }

    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function is virtual to allow for different deployment strategies in derived contracts
     * @param _metadata The metadata of the recipient
     * @param _flowManager The address of the flow manager for the new contract
     * @param _managerRewardPool The address of the manager reward pool for the new contract
     * @return address The address of the newly created Flow contract
     */
    function _deployFlowRecipient(
        RecipientMetadata calldata _metadata,
        address _flowManager,
        address _managerRewardPool
    ) internal virtual returns (address);

    /**
     * @notice Virtual function to be called after updating the reward pool flow
     * @dev This function can be overridden in derived contracts to implement custom logic
     * @param newFlowRate The new flow rate to the reward pool
     */
    function _afterRewardPoolFlowUpdate(int96 newFlowRate) internal virtual {
        // Default implementation does nothing
        // Derived contracts can override this function to add custom logic
    }

    /**
     * @notice Removes a recipient for receiving funds
     * @param recipientId The ID of the recipient to be approved
     * @dev Only callable by the manager of the contract
     * @dev Emits a RecipientRemoved event if the recipient is successfully removed
     */
    function removeRecipient(bytes32 recipientId) external onlyManager nonReentrant {
        (address recipientAddress, RecipientType recipientType) = fs.removeRecipient(recipientId);

        if (recipientType == RecipientType.FlowContract) {
            _childFlows.remove(recipientAddress);
        }

        emit RecipientRemoved(recipientAddress, recipientId);

        _removeFromPools(recipientAddress);
    }

    /**
     * @notice Resets the flow distribution after removing a recipient
     * @dev This function should be called after removing a recipient to ensure proper flow rate distribution
     * @param recipientAddress The address of the removed recipient
     */
    function _removeFromPools(address recipientAddress) internal {
        int96 totalFlowRate = getTotalFlowRate();
        _updateBonusMemberUnits(recipientAddress, 0);
        _updateBaselineMemberUnits(recipientAddress, 0);

        // limitation of superfluid means that when total member units decrease, you must call `distributeFlow` again
        _setFlowRate(totalFlowRate);
    }

    /**
     * @notice Sets the flow rate for a child Flow contract
     * @param childAddress The address of the child Flow contract
     */
    function _setChildFlowRate(address childAddress) internal {
        if (!_childFlows.contains(childAddress)) revert NOT_A_VALID_CHILD_FLOW();

        (bool shouldTransfer, uint256 transferAmount, uint256 balanceRequiredToStartFlow) = fs
            .calculateBufferAmountForChild(
                childAddress,
                address(this),
                getMemberTotalFlowRate(childAddress),
                PERCENTAGE_SCALE
            );

        if (shouldTransfer) {
            fs.superToken.transfer(childAddress, transferAmount);
        }

        // Call setFlowRate on the child contract
        // only set if balance of contract is greater than buffer required
        if (balanceRequiredToStartFlow <= fs.superToken.balanceOf(childAddress)) {
            IFlow(childAddress).setFlowRate(getMemberTotalFlowRate(childAddress));
        }
    }

    /**
     * @notice Connects this contract to a Superfluid pool
     * @param poolAddress The address of the Superfluid pool to connect to
     * @dev Only callable by the owner or parent of the contract
     * @dev Emits a PoolConnected event upon successful connection
     */
    function connectPool(ISuperfluidPool poolAddress) external onlyOwnerOrParent nonReentrant {
        if (address(poolAddress) == address(0)) revert ADDRESS_ZERO();

        bool success = fs.superToken.connectPool(poolAddress);
        if (!success) revert POOL_CONNECTION_FAILED();
    }

    /**
     * @notice Updates the member units in the Superfluid pool
     * @param member The address of the member whose units are being updated
     * @param units The new number of units to be assigned to the member
     * @dev Reverts with UNITS_UPDATE_FAILED if the update fails
     */
    function _updateBonusMemberUnits(address member, uint128 units) internal {
        bool success = fs.superToken.updateMemberUnits(fs.bonusPool, member, units);

        if (!success) revert UNITS_UPDATE_FAILED();
    }

    /**
     * @notice Updates the member units for the baseline Superfluid pool
     * @param member The address of the member whose units are being updated
     * @param units The new number of units to be assigned to the member
     * @dev Reverts with UNITS_UPDATE_FAILED if the update fails
     */
    function _updateBaselineMemberUnits(address member, uint128 units) internal {
        bool success = fs.superToken.updateMemberUnits(fs.baselinePool, member, units);

        if (!success) revert UNITS_UPDATE_FAILED();
    }

    /**
     * @notice Sets the flow rate for the Superfluid pool
     * @param _flowRate The new flow rate to be set
     * @dev Only callable by the owner or parent of the contract
     * @dev Emits a FlowRateUpdated event with the old and new flow rates
     */
    function setFlowRate(int96 _flowRate) external onlyOwnerOrParent nonReentrant {
        fs.cachedFlowRate = _flowRate;
        _setFlowRate(_flowRate);
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
     * @dev Only callable by the current owner
     * @dev Emits a ManagerUpdated event with the old and new manager addresses
     */
    function setManager(address _newManager) external onlyOwnerOrManager nonReentrant {
        if (_newManager == address(0)) revert ADDRESS_ZERO();

        address oldManager = fs.manager;
        fs.manager = _newManager;
        emit ManagerUpdated(oldManager, _newManager);
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

        int96 rewardPoolFlowRate = getManagerRewardPoolFlowRate();

        if (_newManagerRewardFlowRate > 0) {
            // if flow to reward pool is 0, create a flow, otherwise update the flow
            if (rewardPoolFlowRate == 0) {
                // todo need to check this - could it go to 0, then back to > 0 without needing to create a new flow?
                fs.superToken.createFlow(fs.managerRewardPool, _newManagerRewardFlowRate);
            } else {
                fs.superToken.updateFlow(fs.managerRewardPool, _newManagerRewardFlowRate);
            }
        } else if (rewardPoolFlowRate > 0 && _newManagerRewardFlowRate == 0) {
            // only delete if the flow rate is going to 0 and reward pool flow rate is currently > 0
            fs.superToken.deleteFlow(address(this), fs.managerRewardPool);
        }
        _afterRewardPoolFlowUpdate(_newManagerRewardFlowRate);
    }

    /**
     * @notice Internal function to set the flow rate for the Superfluid pools and the manager reward pool
     * @param _flowRate The new flow rate to be set
     * @dev Emits a FlowRateUpdated event with the old and new flow rates
     */
    function _setFlowRate(int96 _flowRate) internal {
        // if total member units is 0, set 1 member unit to this contract
        // do this to prevent distribution pool from resetting flow rate to 0
        if (fs.bonusPool.getTotalUnits() == 0) {
            _updateBonusMemberUnits(address(this), 1);
        }
        if (fs.baselinePool.getTotalUnits() == 0) {
            _updateBaselineMemberUnits(address(this), 1);
        }

        if (_flowRate < 0) revert FLOW_RATE_NEGATIVE();
        int96 oldTotalFlowRate = getTotalFlowRate();

        (int96 baselineFlowRate, int96 bonusFlowRate, int96 managerRewardFlowRate) = fs.calculateFlowRates(
            _flowRate,
            PERCENTAGE_SCALE
        );

        _setFlowToManagerRewardPool(managerRewardFlowRate);

        emit FlowRateUpdated(oldTotalFlowRate, _flowRate, baselineFlowRate, bonusFlowRate, managerRewardFlowRate);

        fs.superToken.distributeFlow(address(this), fs.bonusPool, bonusFlowRate);
        fs.superToken.distributeFlow(address(this), fs.baselinePool, baselineFlowRate);

        // changing flow rate means we need to update all child flow rates
        _setCappedChildFlowRates(address(0));
    }

    /**
     * @notice Sets the baseline flow rate percentage
     * @param _baselineFlowRatePercent The new baseline flow rate percentage
     * @dev Only callable by the owner or manager of the contract
     * @dev Emits a BaselineFlowRatePercentUpdated event with the old and new percentages
     */
    function setBaselineFlowRatePercent(uint32 _baselineFlowRatePercent) external onlyOwnerOrManager nonReentrant {
        if (_baselineFlowRatePercent > PERCENTAGE_SCALE) revert INVALID_PERCENTAGE();

        emit BaselineFlowRatePercentUpdated(fs.baselinePoolFlowRatePercent, _baselineFlowRatePercent);

        fs.baselinePoolFlowRatePercent = _baselineFlowRatePercent;

        // Update flow rates to reflect the new percentage
        _setFlowRate(getTotalFlowRate());
    }

    /**
     * @notice Sets the manager reward flow rate percentage
     * @param _managerRewardFlowRatePercent The new manager reward flow rate percentage
     * @dev Only callable by the owner or manager of the contract
     * @dev Emits a ManagerRewardFlowRatePercentUpdated event with the old and new percentages
     */
    function setManagerRewardFlowRatePercent(uint32 _managerRewardFlowRatePercent) external onlyOwner nonReentrant {
        if (_managerRewardFlowRatePercent > PERCENTAGE_SCALE) revert INVALID_PERCENTAGE();

        emit ManagerRewardFlowRatePercentUpdated(fs.managerRewardPoolFlowRatePercent, _managerRewardFlowRatePercent);

        fs.managerRewardPoolFlowRatePercent = _managerRewardFlowRatePercent;

        // Update flow rates to reflect the new percentage
        _setFlowRate(getTotalFlowRate());
    }

    /**
     * @notice Let's the owner set the metadata for the flow
     * @param metadata The metadata of the flow
     */
    function setMetadata(RecipientMetadata memory metadata) external onlyOwner {
        FlowRecipients.validateMetadata(metadata);
        fs.metadata = metadata;
        emit MetadataSet(metadata);
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
     * @notice Retrieves the total amount received by a specific member in the pool
     * @param memberAddr The address of the member
     * @return totalAmountReceived The total amount received by the member
     */
    function getTotalReceivedByMember(address memberAddr) external view returns (uint256 totalAmountReceived) {
        totalAmountReceived =
            fs.bonusPool.getTotalAmountReceivedByMember(memberAddr) +
            fs.baselinePool.getTotalAmountReceivedByMember(memberAddr);
    }

    /**
     * @return totalFlowRate The total flow rate of the pools and the manager reward pool
     */
    function getTotalFlowRate() public view returns (int96) {
        return fs.cachedFlowRate;
    }

    /**
     * @notice Retrieves all vote allocations for a given ERC721 tokenId
     * @param tokenId The tokenId of the account to retrieve votes for
     * @return allocations An array of VoteAllocation structs representing each vote made by the token
     */
    function getVotesForTokenId(uint256 tokenId) external view returns (VoteAllocation[] memory allocations) {
        return fs.votes[tokenId];
    }

    /**
     * @notice Retrieves all vote allocations for multiple ERC721 tokenIds
     * @param tokenIds An array of tokenIds to retrieve votes for
     * @return allocations An array of arrays, where each inner array contains VoteAllocation structs for a tokenId
     */
    function getVotesForTokenIds(uint256[] calldata tokenIds) public view returns (VoteAllocation[][] memory) {
        return fs.getVotesForTokenIds(tokenIds);
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
     * @notice Retrieves the token vote weight
     * @return uint256 The token vote weight
     */
    function tokenVoteWeight() external view returns (uint256) {
        return fs.tokenVoteWeight;
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
     * @notice Retrieves the manager reward pool address
     * @return address The address of the manager reward pool
     */
    function managerRewardPool() external view returns (address) {
        return fs.managerRewardPool;
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
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param _newImpl The new implementation address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
