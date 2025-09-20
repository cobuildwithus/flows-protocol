// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { IAllocationStrategy } from "../interfaces/IAllocationStrategy.sol";
import { IERC721Votes } from "../interfaces/IERC721Votes.sol";

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ERC721VotesStrategy is IAllocationStrategy, UUPSUpgradeable, Ownable2StepUpgradeable {
    IERC721Votes public token;

    uint256 public tokenVoteWeight;

    // Key under which this strategy expects its config in the JSON blob (unquoted).
    string public constant STRATEGY_KEY = "ERC721Votes";

    event ERC721VotesTokenChanged(address indexed oldToken, address indexed newToken);
    event TokenVoteWeightChanged(uint256 oldWeight, uint256 newWeight);

    constructor() {}

    function initialize(address _initialOwner, IERC721Votes _token, uint256 _tokenVoteWeight) external initializer {
        if (address(_token) == address(0)) revert ADDRESS_ZERO();
        token = _token;
        tokenVoteWeight = _tokenVoteWeight;
        emit ERC721VotesTokenChanged(address(0), address(_token));
        emit TokenVoteWeightChanged(0, _tokenVoteWeight);

        __Ownable2Step_init();
        __UUPSUpgradeable_init();

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

    function canAccountAllocate(address account) external view returns (bool) {
        return accountAllocationWeight(account) > 0;
    }

    function accountAllocationWeight(address account) public view returns (uint256) {
        return token.getVotes(account) * tokenVoteWeight;
    }

    function totalAllocationWeight() external view returns (uint256) {
        return token.totalSupply() * tokenVoteWeight;
    }

    function strategyKey() external pure override returns (string memory) {
        return STRATEGY_KEY;
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     */
    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
