// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.28;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { ERC20VotesUpgradeable } from "./base/erc20/ERC20VotesUpgradeable.sol";

import { IERC20VotesMintable } from "./interfaces/IERC20VotesMintable.sol";
import { IRewardPool } from "./interfaces/IRewardPool.sol";

contract ERC20VotesMintable is
    IERC20VotesMintable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC20VotesUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;

    // An address who has permissions to mint tokens
    address public minter;

    // Whether the minter can be updated
    bool public isMinterLocked;

    // The address of the reward pool
    address public rewardPool;

    EnumerableSet.AddressSet private _ignoreRewardsAddresses;

    error POOL_UNITS_OVERFLOW();

    ///                                                          ///
    ///                          MODIFIERS                       ///
    ///                                                          ///

    /**
     * @notice Require that the minter has not been locked.
     */
    modifier whenMinterNotLocked() {
        if (isMinterLocked) revert MINTER_LOCKED();
        _;
    }

    /**
     * @notice Require that the sender is the minter.
     */
    modifier onlyMinter() {
        if (msg.sender != minter) revert NOT_MINTER();
        _;
    }

    ///                                                          ///
    ///                         CONSTRUCTOR                      ///
    ///                                                          ///

    constructor() initializer {}

    ///                                                          ///
    ///                         INITIALIZER                      ///
    ///                                                          ///

    /**
     * @dev Initializes the ERC20Mintable contract.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     * @notice This function should only be called once during initialization.
     */
    function __ERC20Mintable_init(string calldata _name, string calldata _symbol) internal onlyInitializing {
        __ReentrancyGuard_init();
        __Ownable2Step_init();
        __ERC20_init(_name, _symbol);
    }

    /**
     * @notice Initializes an ERC-20 mintable token contract
     * @param _initialOwner The address of the initial owner
     * @param _minter The address of the minter
     * @param _rewardPool The address of the reward pool
     * @param _ignoreRewardsAddressSet The addresses to ignore when updating rewards
     * @param _name The name of the token
     * @param _symbol The symbol of the token
     */
    function initialize(
        address _initialOwner,
        address _minter,
        address _rewardPool,
        address[] memory _ignoreRewardsAddressSet,
        string calldata _name,
        string calldata _symbol
    ) external initializer {
        if (_minter == address(0)) revert INVALID_ADDRESS_ZERO();
        if (_initialOwner == address(0)) revert INVALID_ADDRESS_ZERO();
        if (_rewardPool == address(0)) revert INVALID_ADDRESS_ZERO();

        minter = _minter;
        rewardPool = _rewardPool;

        for (uint256 i = 0; i < _ignoreRewardsAddressSet.length; i++) {
            _ignoreRewardsAddresses.add(_ignoreRewardsAddressSet[i]);
        }

        __ERC20Mintable_init(_name, _symbol);

        _transferOwnership(_initialOwner);

        emit MinterUpdated(_minter);
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the default value returned by this function, unless
     * it's overridden.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override(ERC20Upgradeable, IERC20VotesMintable) returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override(ERC20Upgradeable) returns (uint256) {
        return super.totalSupply();
    }

    function ignoreRewardsAddresses() external view returns (address[] memory) {
        return _ignoreRewardsAddresses.values();
    }

    /**
     * @notice Mints new tokens and assigns them to the specified account
     * @dev Only callable by the minter role and protected against reentrancy
     * @param account The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address account, uint256 amount) public nonReentrant onlyMinter {
        _mint(account, amount);
    }

    ///                                                          ///
    ///                       ACCESS CONTROL                     ///
    ///                                                          ///

    /**
     * @notice Set the token minter.
     * @dev Only callable by the owner when not locked.
     */
    function setMinter(address _minter) external override onlyOwner nonReentrant whenMinterNotLocked {
        if (_minter == address(0)) revert INVALID_ADDRESS_ZERO();
        minter = _minter;

        emit MinterUpdated(_minter);
    }

    /**
     * @notice Lock the minter.
     * @dev This cannot be reversed and is only callable by the owner when not locked.
     */
    function lockMinter() external override onlyOwner whenMinterNotLocked {
        isMinterLocked = true;

        emit MinterLocked();
    }

    function burn(address account, uint256 amount) external onlyMinter {
        _burn(account, amount);
    }

    /**
     * @dev Move voting power when tokens are transferred.
     *
     * Emits a {IVotes-DelegateVotesChanged} event.
     */
    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        super._afterTokenTransfer(from, to, amount);

        // dont let people update rewards pool for same account
        if (from == to) return;

        // update member units in the reward pool
        // and scale back by 1e12 per https://docs.superfluid.finance/docs/protocol/distributions/guides/pools#about-member-units
        // gives someone with 1 token at least 1e6 units to work with

        // if minting from 0 address, don't update member units
        if (from != address(0) && !_ignoreRewardsAddresses.contains(from)) {
            uint256 units = balanceOf(from) / 1e12;
            if (units > type(uint128).max) revert POOL_UNITS_OVERFLOW();
            uint128 fromUnits = uint128(units);
            IRewardPool(rewardPool).updateMemberUnits(from, fromUnits);
        }

        // if transferring to 0 address, don't update member units
        if (to != address(0) && !_ignoreRewardsAddresses.contains(to)) {
            uint256 units = balanceOf(to) / 1e12;
            if (units > type(uint128).max) revert POOL_UNITS_OVERFLOW();
            uint128 toUnits = uint128(units);
            IRewardPool(rewardPool).updateMemberUnits(to, toUnits);
        } else {
            // burning tokens here since to is the 0 address
            // limitation of superfluid means that when total member units decrease, you must call `distributeFlow` again
            IRewardPool(rewardPool).resetFlowRate();
        }
    }

    ///                                                          ///
    ///                       TOKEN UPGRADE                      ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
