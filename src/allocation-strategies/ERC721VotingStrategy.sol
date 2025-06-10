// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { IAllocationStrategy } from "../interfaces/IAllocationStrategy.sol";
import { IERC721Checkpointable } from "../interfaces/IERC721Checkpointable.sol";

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ERC721VotingStrategy is IAllocationStrategy, UUPSUpgradeable, Ownable2StepUpgradeable {
    IERC721Checkpointable public token;

    uint256 public tokenVoteWeight;

    constructor() {}

    function initialize(
        address _initialOwner,
        IERC721Checkpointable _token,
        uint256 _tokenVoteWeight
    ) external initializer {
        if (address(_token) == address(0)) revert ADDRESS_ZERO();
        token = _token;
        tokenVoteWeight = _tokenVoteWeight;

        _transferOwnership(_initialOwner);
    }

    function allocationKey(address, bytes calldata aux) external pure returns (uint256) {
        uint256 tokenId = abi.decode(aux, (uint256));
        return tokenId;
    }

    function currentWeight(uint256) external view returns (uint256) {
        return tokenVoteWeight;
    }

    function canAllocate(uint256 tokenId, address caller) external view returns (bool) {
        address tokenOwner = token.ownerOf(tokenId);
        // check if the token owner has delegated their voting power to the caller
        // erc721checkpointable falls back to the owner
        // if the owner hasn't delegated so this will work for the owner as well
        address delegate = token.delegates(tokenOwner);
        return caller == delegate;
    }

    function totalAllocationWeight() external view returns (uint256) {
        return token.totalSupply() * tokenVoteWeight;
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param _newImpl The new implementation address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
