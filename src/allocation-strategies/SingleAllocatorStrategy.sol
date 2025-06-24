// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { IAllocationStrategy } from "../interfaces/IAllocationStrategy.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract SingleAllocatorStrategy is IAllocationStrategy, UUPSUpgradeable, Ownable2StepUpgradeable {
    address public allocator;

    // The virtual weight used for sub-BPS resolution in allocation calculations
    uint256 public constant VIRTUAL_WEIGHT = 1e24;

    // Strategy JSON key exposed to front-end helpers (unquoted).
    string public constant STRATEGY_KEY = "SingleAllocator";

    event AllocatorChanged(address indexed oldAllocator, address indexed newAllocator);

    constructor() {}

    function initialize(address _initialOwner, address _allocator) external initializer {
        if (_allocator == address(0)) revert ADDRESS_ZERO();
        allocator = _allocator;
        emit AllocatorChanged(address(0), _allocator);

        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        _transferOwnership(_initialOwner);
    }

    function allocationKey(address, bytes calldata) external pure returns (uint256) {
        return 0; // one fixed allocation key for all allocations
    }

    function currentWeight(uint256) external view returns (uint256) {
        return VIRTUAL_WEIGHT;
    }

    function canAllocate(uint256, address caller) external view returns (bool) {
        return caller == allocator;
    }

    function canAccountAllocate(address account) external view returns (bool) {
        return account == allocator;
    }

    function accountAllocationWeight(address account) external view returns (uint256) {
        return account == allocator ? VIRTUAL_WEIGHT : 0;
    }

    function totalAllocationWeight() external view returns (uint256) {
        return 0; // no quorum necessary for this strategy
    }

    function strategyKey() external pure override returns (string memory) {
        return STRATEGY_KEY;
    }

    /// Optional: owner can hand the baton to a new allocator.
    function changeAllocator(address newAllocator) external onlyOwner {
        require(newAllocator != address(0), "new allocator: zero");
        allocator = newAllocator;
        emit AllocatorChanged(allocator, newAllocator);
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     */
    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
