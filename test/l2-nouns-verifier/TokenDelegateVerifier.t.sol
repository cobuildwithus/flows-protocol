// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @author Wilson Cusack (https://github.com/wilsoncusack/state-proof-poc)

import { TokenVerifierTest } from "./TokenVerifier.t.sol";

import { TokenVerifier } from "../../src/state-proof/TokenVerifier.sol";
import { IStateProof } from "../../src/interfaces/IStateProof.sol";

contract L2NounsDelegateVerifier is TokenVerifierTest {
    function test__isOwnDelegateHasDelegatedToSelf() public {
        address account = 0x77D920b4d1163DbC516E7Ce70596225D17819dC5;
        vm.createSelectFork(vm.rpcUrl("base"), 19354086);
        TokenVerifier verifier = new TokenVerifier(NOUNS_TOKEN_ADDRESS);
        string memory rootPath = vm.projectRoot();

        string memory path = string.concat(rootPath, "/test/proof-data/_delegates/", vm.toString(account), ".json");

        IStateProof.Parameters memory delegationParams = getStateProofParams(path);

        assertTrue(verifier.isDelegate(account, account, delegationParams));
    }

    function test__isDelegateFails_DifferentAddress() public {
        address account = 0x77D920b4d1163DbC516E7Ce70596225D17819dC5;
        address differentAccount = 0x1234567890123456789012345678901234567890; // A different address
        vm.createSelectFork(vm.rpcUrl("base"), 19354086);
        TokenVerifier verifier = new TokenVerifier(NOUNS_TOKEN_ADDRESS);
        string memory rootPath = vm.projectRoot();

        string memory path = string.concat(rootPath, "/test/proof-data/_delegates/", vm.toString(account), ".json");

        IStateProof.Parameters memory delegationParams = getStateProofParams(path);

        assertFalse(verifier.isDelegate(account, differentAccount, delegationParams));
    }

    // check that even if they have not explicitly delegated to self, they are still an owner delegate
    function test__isOwnerDelegateNotDelegated() public {
        address account = 0xbc3ed6B537f2980e66f396Fe14210A56ba3f72C4;
        vm.createSelectFork(vm.rpcUrl("base"), 19952328);
        TokenVerifier verifier = new TokenVerifier(NOUNS_TOKEN_ADDRESS);
        string memory rootPath = vm.projectRoot();

        string memory path = string.concat(rootPath, "/test/proof-data/_delegates/", vm.toString(account), ".json");

        IStateProof.Parameters memory delegationParams = getStateProofParams(path);

        assertTrue(verifier.isDelegate(account, account, delegationParams));
    }

    // test for when not delegated to self, but passing another address
    function test__isOwnerDelegateNotDelegated_DifferentAddress() public {
        address account = 0xbc3ed6B537f2980e66f396Fe14210A56ba3f72C4;
        address differentAccount = 0x1234567890123456789012345678901234567890; // A different address
        vm.createSelectFork(vm.rpcUrl("base"), 19952328);
        TokenVerifier verifier = new TokenVerifier(NOUNS_TOKEN_ADDRESS);
        string memory rootPath = vm.projectRoot();

        string memory path = string.concat(rootPath, "/test/proof-data/_delegates/", vm.toString(account), ".json");

        IStateProof.Parameters memory delegationParams = getStateProofParams(path);

        assertFalse(verifier.isDelegate(account, differentAccount, delegationParams));
    }
}
