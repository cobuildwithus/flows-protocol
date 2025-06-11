// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { IAllocationStrategy } from "../interfaces/IAllocationStrategy.sol";
import { IERC721Checkpointable } from "../interfaces/IERC721Checkpointable.sol";

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { JSONParserLib as JSON } from "solady/utils/JSONParserLib.sol";
using JSON for JSON.Item;

contract ERC721VotingStrategy is IAllocationStrategy, UUPSUpgradeable, Ownable2StepUpgradeable {
    IERC721Checkpointable public token;

    uint256 public tokenVoteWeight;

    event ERC721VotingTokenChanged(address indexed oldToken, address indexed newToken);
    event TokenVoteWeightChanged(uint256 oldWeight, uint256 newWeight);

    error EMPTY_TOKEN_IDS();
    error NOT_ARRAY();

    constructor() {}

    function initialize(
        address _initialOwner,
        IERC721Checkpointable _token,
        uint256 _tokenVoteWeight
    ) external initializer {
        if (address(_token) == address(0)) revert ADDRESS_ZERO();
        token = _token;
        tokenVoteWeight = _tokenVoteWeight;
        emit ERC721VotingTokenChanged(address(0), address(_token));
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

    function totalAllocationWeight() external view returns (uint256) {
        return token.totalSupply() * tokenVoteWeight;
    }

    function buildAllocationData(address, string memory json) external pure override returns (bytes[] memory) {
        // Parse the JSON & drill into the "tokenIds" field.
        JSON.Item memory root = JSON.parse(json);
        JSON.Item memory tokenIdsItem = root.at('"tokenIds"');

        // Must be an array.
        if (!JSON.isArray(tokenIdsItem)) revert NOT_ARRAY();

        uint256 len = JSON.size(tokenIdsItem);
        if (len == 0) revert EMPTY_TOKEN_IDS();

        bytes[] memory aux = new bytes[](len);

        for (uint256 i = 0; i < len; i++) {
            JSON.Item memory idItem = tokenIdsItem.at(i);
            string memory valueStr = JSON.value(idItem);
            if (JSON.isString(idItem)) {
                valueStr = JSON.decodeString(valueStr);
            }
            uint256 tokenId = JSON.parseUint(valueStr);
            aux[i] = abi.encode(tokenId);
        }

        // Return the packed aux array (one element per tokenId).
        return aux;
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     */
    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
