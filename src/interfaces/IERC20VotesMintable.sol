// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

/**
 * @title IERC20VotesMintable
 * @dev Interface for an ERC20 token with minting capabilities
 *
 * This interface defines the events, errors, and functions for an ERC20 token
 * that can be minted and has a minter role that can be updated or locked.
 */
interface IERC20VotesMintable {
    /**
     * @dev Emitted when the minter address is updated
     * @param minter The new minter address
     */
    event MinterUpdated(address minter);

    /**
     * @dev Emitted when the minter role is permanently locked
     */
    event MinterLocked();

    /**
     * @dev Emitted when the ignored addresses manager address is updated
     * @param ignoredRewardAddressesManager The new ignored addresses manager address
     */
    event IgnoredRewardAddressesManagerUpdated(address ignoredRewardAddressesManager);

    /**
     * @dev Emitted when an address is added to the ignored addresses list
     * @param account The address that was added
     */
    event IgnoreRewardsAddressAdded(address account);

    /**
     * @dev Emitted when an address is removed from the ignored addresses list
     * @param account The address that was removed
     */
    event IgnoreRewardsAddressRemoved(address account);

    /**
     * @dev Error thrown when a function is called by an address that is not the manager
     */
    error ONLY_MANAGER();

    /**
     * @dev Error thrown when attempting to set an invalid zero address
     */
    error INVALID_ADDRESS_ZERO();

    /**
     * @dev Error thrown when an address is already ignored
     */
    error ALREADY_IGNORED();

    /**
     * @dev Error thrown when an address is not ignored
     */
    error NOT_IGNORED();

    /**
     * @dev Error thrown when the pool units overflow
     */
    error POOL_UNITS_OVERFLOW();

    /**
     * @dev Error thrown when the ignored addresses manager is not the sender
     */
    error NOT_IGNORED_ADDRESSES_MANAGER();

    /**
     * @dev Error thrown when attempting to update the minter after it has been locked
     */
    error MINTER_LOCKED();

    /**
     * @dev Error thrown when a minting function is called by an address that is not the minter
     */
    error NOT_MINTER();

    /**
     * @dev Returns the address of the current minter
     * @return The minter's address
     */
    function minter() external view returns (address);

    /**
     * @dev Sets a new minter address
     * @param minter The address of the new minter
     */
    function setMinter(address minter) external;

    /**
     * @dev Permanently locks the minter role, preventing further changes
     */
    function lockMinter() external;

    /**
     * @dev Mints new tokens and assigns them to the specified account
     * @param account The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address account, uint256 amount) external;

    /**
     * @dev Returns the number of decimals used to get its user representation
     * @return The number of decimals
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the addresses that are ignored when updating rewards
     * @return The addresses
     */
    function ignoreRewardsAddresses() external view returns (address[] memory);

    /**
     * @dev Initializes the ERC20 token contract
     * @param initialOwner The address of the initial owner
     * @param minter The address of the minter
     * @param rewardPool The address of the reward pool
     * @param ignoreRewardsAddresses The addresses to ignore when updating rewards
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param ignoredRewardAddressesManager The address of the ignored addresses manager
     */
    function initialize(
        address initialOwner,
        address minter,
        address rewardPool,
        address[] memory ignoreRewardsAddresses,
        string calldata name,
        string calldata symbol,
        address ignoredRewardAddressesManager
    ) external;

    /**
     * @dev Adds an address to the ignored addresses list
     * @param account The address to add
     */
    function addIgnoredRewardsAddress(address account) external;

    /**
     * @dev Removes an address from the ignored addresses list
     * @param account The address to remove
     */
    function removeIgnoredRewardsAddress(address account) external;
}
