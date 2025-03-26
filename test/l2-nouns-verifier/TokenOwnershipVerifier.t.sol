// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @author Wilson Cusack (https://github.com/wilsoncusack/state-proof-poc)

import { TokenVerifierTest } from "./TokenVerifier.t.sol";

import { TokenVerifier } from "../../src/state-proof/TokenVerifier.sol";
import { IStateProof } from "../../src/interfaces/IStateProof.sol";

contract L2NounsOwnershipVerifierTest is TokenVerifierTest {
    function test__isOwner() public {
        uint256 tokenId = 256;
        vm.createSelectFork(vm.rpcUrl("base"), 19354086);
        TokenVerifier verifier = new TokenVerifier(NOUNS_TOKEN_ADDRESS);
        string memory rootPath = vm.projectRoot();
        string memory path = string.concat(rootPath, "/test/proof-data/_owners/", vm.toString(tokenId), ".json");

        IStateProof.Parameters memory params = getStateProofParams(path);

        assertTrue(verifier.isOwner(tokenId, 0xb1a32FC9F9D8b2cf86C068Cae13108809547ef71, params));

        // try to mess with timestamp and make a past proof for the future
        params.beaconOracleTimestamp += 1;
        vm.expectRevert();
        verifier.isOwner(tokenId, 0xb1a32FC9F9D8b2cf86C068Cae13108809547ef71, params);
    }

    function test__isNotOwner() public {
        uint256 tokenId = 256;
        vm.createSelectFork(vm.rpcUrl("base"), 19354086);
        TokenVerifier verifier = new TokenVerifier(NOUNS_TOKEN_ADDRESS);
        string memory rootPath = vm.projectRoot();
        string memory path = string.concat(rootPath, "/test/proof-data/_owners/", vm.toString(tokenId), ".json");

        IStateProof.Parameters memory params = getStateProofParams(path);

        vm.expectRevert(abi.encodeWithSignature("StorageProofVerificationFailed()"));
        verifier.isOwner(tokenId, 0x0000000000000000000000000000000000000000, params);
    }
}
