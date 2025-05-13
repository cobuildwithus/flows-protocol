// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { IFlow } from "../src/interfaces/IFlow.sol";
import { FlowTypes } from "../src/storage/FlowStorage.sol";

contract AddVrbsTestRecipients is DeployScript {
    // address of the existing VrbsFlow contract
    address public constant FLOW_ADDRESS = 0xe596992b71b57D5A5bF730006a019Df363F43976;

    function deploy() internal override {
        IFlow vrbsFlow = IFlow(FLOW_ADDRESS);

        // prepare metadata for Vrbs Soccer [TEST]
        FlowTypes.RecipientMetadata memory soccerMeta = FlowTypes.RecipientMetadata({
            title: "Vrbs Soccer [TEST]",
            description: "We make good soccer merch and run games for a good cause",
            image: "ipfs://bafkreigszo5xzijor5hge435icuxrhshsiwdqhydx7zgpksoced4dgh4aa",
            tagline: "Good Games for a Good Cause",
            url: "https://realmadrid.com"
        });

        // prepare metadata for Vrbs Coffee [TEST]
        FlowTypes.RecipientMetadata memory coffeeMeta = FlowTypes.RecipientMetadata({
            title: "Vrbs Coffee [TEST]",
            description: "Good Coffee for a Good Cause",
            image: "ipfs://bafkreigszo5xzijor5hge435icuxrhshsiwdqhydx7zgpksoced4dgh4aa",
            tagline: "Good Coffee for a Good Cause",
            url: "https://vrbscoffee.com"
        });

        // add Vrbs Soccer recipient
        vrbsFlow.addRecipient(
            0x6b646cc82f536bb69dfbea1ed930066e2150da81a11f9178bf2eb770100ca3a6,
            0x2830e21792019CE670fBc548AacB004b08c7f71f,
            soccerMeta
        );
        // add Vrbs Coffee recipient
        vrbsFlow.addRecipient(
            0x999bfac23af3c9817504d270c65c1e07fc4865de52500c16e6b3226317cba480,
            0x289715fFBB2f4b482e2917D2f183FeAb564ec84F,
            coffeeMeta
        );
        vm.stopBroadcast();
    }

    function writeAdditionalDeploymentDetails(string memory) internal override {
        // no additional details to write
    }

    function getContractName() internal pure override returns (string memory) {
        return "VrbsFlow";
    }
}
