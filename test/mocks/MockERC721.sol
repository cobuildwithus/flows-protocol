// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { ERC721Checkpointable } from "../../src/base/nouns-token/ERC721Checkpointable.sol";
import { ERC721 } from "../../src/base/nouns-token/ERC721.sol";

contract MockERC721 is ERC721Checkpointable {
    mapping(address => address) private _delegates;

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

    function mint(address _to, uint256 _tokenId) public {
        _mint(address(this), _to, _tokenId);
    }
}
