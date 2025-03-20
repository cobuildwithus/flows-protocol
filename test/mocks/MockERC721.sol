// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721Checkpointable } from "../../src/interfaces/IERC721Checkpointable.sol";

contract MockERC721 is ERC721, IERC721Checkpointable {
    mapping(address => address) private _delegates;

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

    function mint(address _to, uint256 _tokenId) public {
        _mint(_to, _tokenId);
    }

    function delegates(address delegator) public view override returns (address) {
        address current = _delegates[delegator];
        return current == address(0) ? delegator : current;
    }

    function delegate(address delegatee) public {
        require(delegatee != address(0), "Cannot delegate to zero address");
        _delegates[msg.sender] = delegatee;
    }

    // Stub implementations for IERC721Checkpointable
    function getCurrentVotes(address) external pure override returns (uint96) {
        return 0;
    }

    function getPriorVotes(address, uint256) external pure override returns (uint96) {
        return 0;
    }

    // Implementations for IERC721Enumerable functions
    function tokenByIndex(uint256 index) external view override returns (uint256) {
        // This is a mock implementation, returning a dummy value
        return index;
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) external view override returns (uint256) {
        // This is a mock implementation, returning a dummy value
        return index;
    }

    function totalSupply() external view override returns (uint256) {
        // This is a mock implementation, returning a dummy value
        return 0;
    }
}
