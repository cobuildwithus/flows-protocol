// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { IFlow } from "../../src/interfaces/IFlow.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";

interface IFlowBulkAdd {
    function bulkAddRecipients(
        bytes32[] calldata recipientIds,
        address[] calldata recipients,
        FlowTypes.RecipientMetadata[] calldata metadatas
    ) external returns (bytes32[] memory, address[] memory);
}

contract BulkAddRecipientsBaseForkTest is Test {
    address internal constant FLOW_ADDRESS = 0x9C95FC28b6Be5157f3e1C7d760545bad37e228e0;
    address internal constant FLOW_MANAGER = 0xb9d58f3575BF264cf705C15fcFa06EB4AFDcEa64;

    function testFork_bulkAddExistingRecipientsReverts() public {
        string memory baseRpcUrl = vm.envOr("RPC_BASE", string(""));
        if (bytes(baseRpcUrl).length == 0) {
            emit log("Skipping: RPC_BASE not set");
            return;
        }

        uint256 forkBlock = vm.envOr("BASE_FORK_BLOCK", uint256(0));
        if (forkBlock > 0) {
            vm.createSelectFork(baseRpcUrl, forkBlock);
        } else {
            vm.createSelectFork(baseRpcUrl);
        }

        bytes32[] memory recipientIds = new bytes32[](3);
        recipientIds[0] = 0x9066d0395e906bbf0fa352178f958cff49cd538f55448493db8225f41989c451;
        recipientIds[1] = 0xc64a0b4141e3a35db01f1e190a9f7755d774dc0c31e58feaff9bbbbb58e92ebd;
        recipientIds[2] = 0x27558898c0465ea32ecf16a241b7e5ff587288276d9c099a0a2f05efd919ca4f;

        address[] memory recipients = new address[](3);
        recipients[0] = 0x2f528b5AD9f5dd221894251FD716B8B37E423C81;
        recipients[1] = 0x4a3e6E66f8C32bC05A50879f872B1177A1573CDF;
        recipients[2] = 0x0FC10c96a6BDc43969dB74CD8E788033748dA0B9;

        FlowTypes.RecipientMetadata[] memory metadatas = new FlowTypes.RecipientMetadata[](3);
        metadatas[0] = FlowTypes.RecipientMetadata({
            title: "SVVVG3",
            description: "Collector and builder",
            image: "https://imagedelivery.net/example/a543c5fa",
            tagline: "@svvvg3",
            url: "https://farcaster.xyz/svvvg3"
        });
        metadatas[1] = FlowTypes.RecipientMetadata({
            title: "Drake",
            description: "Artist and gardener",
            image: "https://imagedelivery.net/example/c0def01a",
            tagline: "@taliskye",
            url: "https://farcaster.xyz/taliskye"
        });
        metadatas[2] = FlowTypes.RecipientMetadata({
            title: "Optic",
            description: "Artist and merch builder",
            image: "https://imagedelivery.net/example/c87049f1",
            tagline: "@beatsbyoptic",
            url: "https://farcaster.xyz/beatsbyoptic"
        });

        vm.startPrank(FLOW_MANAGER);
        IFlowBulkAdd(FLOW_ADDRESS).bulkAddRecipients(recipientIds, recipients, metadatas);
        vm.stopPrank();
    }
}
