// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @author Wilson Cusack (https://github.com/wilsoncusack/state-proof-poc)

import { stdJson } from "forge-std/StdJson.sol";
import { TokenVerifierTest } from "./TokenVerifier.t.sol";

import { StateVerifier } from "../../src/state-proof/StateVerifier.sol";
import { TokenVerifier } from "../../src/state-proof/TokenVerifier.sol";
import { IStateProof } from "../../src/interfaces/IStateProof.sol";

contract L2NounsVotingVerifier is TokenVerifierTest {
    using stdJson for string;

    function test__isOwnDelegateNoNouns() public {
        uint256 tokenId = 256;
        address account = 0x77D920b4d1163DbC516E7Ce70596225D17819dC5;

        vm.createSelectFork(vm.rpcUrl("base"), 19354086);
        TokenVerifier verifier = new TokenVerifier(NOUNS_TOKEN_ADDRESS);

        string memory rootPath = vm.projectRoot();
        string memory delegatePath = string.concat(
            rootPath,
            "/test/proof-data/_delegates/",
            vm.toString(account),
            ".json"
        );

        IStateProof.Parameters memory delegationParams = getStateProofParams(delegatePath);

        assertTrue(verifier.isDelegate(account, account, delegationParams));

        // this account owns no nouns - try to vote with wilsons token
        string memory ownershipPath = string.concat(
            rootPath,
            "/test/proof-data/_owners/",
            vm.toString(tokenId),
            ".json"
        );
        IStateProof.Parameters memory params = getStateProofParams(ownershipPath);

        vm.expectRevert(abi.encodeWithSignature("StorageProofVerificationFailed()"));
        verifier.canVoteWithToken(tokenId, account, account, params, params);
    }

    function test__isDelegatedNouns() public {
        address delegate = 0xE30AcDdC6782d82C0CBE00349c27CB4E78C51510;
        address vaultNoun40 = 0xa555d1Ee16780B2d414eD97f4f169c0740099615;
        uint256 tokenId = 40;

        vm.createSelectFork(vm.rpcUrl("base"), 19382037);
        TokenVerifier verifier = new TokenVerifier(NOUNS_TOKEN_ADDRESS);

        string memory rootPath = vm.projectRoot();
        string memory delegatePath = string.concat(
            rootPath,
            "/test/proof-data/_delegates/",
            vm.toString(vaultNoun40),
            ".json"
        );
        string memory ownershipPath = string.concat(
            rootPath,
            "/test/proof-data/_owners/",
            vm.toString(tokenId),
            ".json"
        );

        IStateProof.Parameters memory delegateProof = getStateProofParams(delegatePath);
        IStateProof.Parameters memory ownershipProof = getStateProofParams(ownershipPath);

        assertTrue(verifier.isDelegate(vaultNoun40, delegate, delegateProof));
        assertFalse(verifier.isDelegate(vaultNoun40, vaultNoun40, delegateProof));
        assertTrue(verifier.isOwner(tokenId, vaultNoun40, ownershipProof));
        assertTrue(verifier.canVoteWithToken(tokenId, vaultNoun40, delegate, ownershipProof, delegateProof));

        // can't vote with your own token that is delegated out
        assertFalse(verifier.canVoteWithToken(tokenId, vaultNoun40, vaultNoun40, ownershipProof, delegateProof));
    }

    function test__willywonkaProof() public {
        address delegate = 0x05A1ff0a32bc24265BCB39499d0c5D9A6cb2011c;
        address owner = 0x05A1ff0a32bc24265BCB39499d0c5D9A6cb2011c;
        uint256 tokenId = 1016;
        vm.createSelectFork(vm.rpcUrl("base"), 21718459);
        TokenVerifier verifier = new TokenVerifier(NOUNS_TOKEN_ADDRESS);

        string memory rootPath = vm.projectRoot();
        string memory delegatePath = string.concat(
            rootPath,
            "/test/proof-data/_delegates/",
            vm.toString(owner),
            ".json"
        );
        string memory ownershipPath = string.concat(
            rootPath,
            "/test/proof-data/_owners/",
            vm.toString(tokenId),
            ".json"
        );

        IStateProof.Parameters memory delegateProof = getStateProofParams(delegatePath);
        IStateProof.Parameters memory ownershipProof = getStateProofParams(ownershipPath);

        assertTrue(verifier.isDelegate(owner, delegate, delegateProof));
        assertTrue(verifier.isOwner(tokenId, owner, ownershipProof));
        assertTrue(verifier.canVoteWithToken(tokenId, owner, delegate, ownershipProof, delegateProof));
    }

    // same as above except try to vote with another delegate 0x289715fFBB2f4b482e2917D2f183FeAb564ec84F
    function test__willywonkaProofWithOtherDelegate() public {
        address delegate = 0x289715fFBB2f4b482e2917D2f183FeAb564ec84F;
        address owner = 0x05A1ff0a32bc24265BCB39499d0c5D9A6cb2011c;
        uint256 tokenId = 1016;
        vm.createSelectFork(vm.rpcUrl("base"), 21718950);
        TokenVerifier verifier = new TokenVerifier(NOUNS_TOKEN_ADDRESS);

        string memory rootPath = vm.projectRoot();
        string memory delegatePath = string.concat(
            rootPath,
            "/test/proof-data/_delegates/",
            vm.toString(owner),
            ".json"
        );
        string memory delegateHackerPath = string.concat(
            rootPath,
            "/test/proof-data/_delegates/",
            vm.toString(delegate),
            ".json"
        );
        string memory ownershipPath = string.concat(
            rootPath,
            "/test/proof-data/_owners/",
            vm.toString(tokenId),
            ".json"
        );

        IStateProof.Parameters memory delegateProof = getStateProofParams(delegatePath);
        IStateProof.Parameters memory delegateProofHacker = getStateProofParams(delegateHackerPath);
        IStateProof.Parameters memory ownershipProof = getStateProofParams(ownershipPath);

        // should revert
        assertFalse(verifier.canVoteWithToken(tokenId, owner, delegate, ownershipProof, delegateProof));
        assertFalse(verifier.isDelegate(owner, delegate, delegateProof));
        vm.expectRevert("MerkleTrie: invalid proof provided");
        verifier.isDelegate(owner, delegate, delegateProofHacker);
        assertTrue(verifier.isOwner(tokenId, owner, ownershipProof));
    }
}
