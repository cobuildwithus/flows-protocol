// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { RevolutionFlowTest } from "./RevolutionFlow.t.sol";
import { FlowTypes } from "../../src/storage/FlowStorage.sol";
import { Flow } from "../../src/Flow.sol";
import { SelfManagedFlow } from "../../src/flows/SelfManagedFlow.sol";

contract SelfManagedChildFlowTest is RevolutionFlowTest {
    address public artistsBudget;
    address public accelerator;
    address public realMadrid;
    address public healthAi;
    address public realArtistsBudget;
    address public aiArtistsBudget;

    address riderway = 0x2830e21792019CE670fBc548AacB004b08c7f71f;
    address rocketman = 0x289715fFBB2f4b482e2917D2f183FeAb564ec84F;

    function setUp() public override {
        super.setUp();
    }

    function test_self_managed_child_flow() public {
        vm.startPrank(manager);
        // Create first-level recipients (similar to AddRevolutionTestRecipients.s.sol)
        FlowTypes.RecipientMetadata memory artistsBudgetMeta = FlowTypes.RecipientMetadata({
            title: "Artists Budget",
            description: "Create Vrbs art and media that amplify funded ventures, spark public curiosity about Vrbs, and beautify shared public spaces.",
            image: "ipfs://bafkreifrolsnnjbklsvs5uutiua336m2y33kb2zggj4e3kion5672uuz3u",
            tagline: "Artists welcome",
            url: "https://flows.wtf/vrbs"
        });

        FlowTypes.RecipientMetadata memory acceleratorMeta = FlowTypes.RecipientMetadata({
            title: "Vrbs Accelerator",
            description: unicode"Back and mentor Vrbs-branded ventures that onboard the public to crypto, uplift their communities, and reach break-even within six months—returning a share of revenue to fuel future grants.",
            image: "ipfs://bafkreices36hj7akzelx2jfw6dxmkfxfjis44koxcolkbisqopufcbolju",
            tagline: "Founders welcome",
            url: "https://flows.wtf/vrbs"
        });

        // Add first-level recipients to the main flow
        (, artistsBudget) = flow.addFlowRecipient(
            keccak256(abi.encode(artistsBudgetMeta)),
            artistsBudgetMeta,
            manager,
            address(0),
            bytes("")
        );

        (, accelerator) = flow.addFlowRecipient(
            keccak256(abi.encode(acceleratorMeta)),
            acceleratorMeta,
            manager,
            address(0),
            bytes("")
        );

        address selfManagedFlowImpl = address(new SelfManagedFlow());

        // Create second-level recipients for Accelerator
        FlowTypes.RecipientMetadata memory realMadridMeta = FlowTypes.RecipientMetadata({
            title: "Real Madrid",
            description: "Support Real Madrid's community initiatives and youth development programs through Vrbs ecosystem integration.",
            image: "ipfs://bafkreifrolsnnjbklsvs5uutiua336m2y33kb2zggj4e3kion5672uuz3u",
            tagline: "Football legends",
            url: "https://flows.wtf/vrbs/realmadrid"
        });

        FlowTypes.RecipientMetadata memory healthAiMeta = FlowTypes.RecipientMetadata({
            title: "Vrbs Health AI",
            description: "Develop AI-powered health solutions that leverage blockchain for secure data management and community wellness initiatives.",
            image: "ipfs://bafkreices36hj7akzelx2jfw6dxmkfxfjis44koxcolkbisqopufcbolju",
            tagline: "AI for wellness",
            url: "https://flows.wtf/vrbs/healthai"
        });

        // Add second-level recipients to the Accelerator
        (, realMadrid) = Flow(accelerator).addFlowRecipient(
            keccak256(abi.encode(realMadridMeta)),
            realMadridMeta,
            riderway,
            address(0),
            abi.encode(address(selfManagedFlowImpl), riderway)
        );

        (, healthAi) = Flow(accelerator).addFlowRecipient(
            keccak256(abi.encode(healthAiMeta)),
            healthAiMeta,
            rocketman,
            address(0),
            abi.encode(address(selfManagedFlowImpl), rocketman)
        );

        // Create second-level recipients for Artists Budget
        FlowTypes.RecipientMetadata memory realArtistsBudgetMeta = FlowTypes.RecipientMetadata({
            title: "Real Artists Budget",
            description: "Fund traditional artists and art initiatives that promote cultural heritage and artistic expression within the Vrbs ecosystem.",
            image: "ipfs://bafkreiabcdefghijklmnopqrstuvwxyz123456789abcdefghijklmnopq",
            tagline: "Supporting traditional artists",
            url: "https://flows.wtf/vrbs/realartists"
        });

        FlowTypes.RecipientMetadata memory aiArtistsBudgetMeta = FlowTypes.RecipientMetadata({
            title: "AI Artists Budget",
            description: "Support artists leveraging AI technologies to create innovative digital art and explore the intersection of technology and creativity.",
            image: "ipfs://bafkreizyxwvutsrqponmlkjihgfedcba987654321zyxwvutsrqponmlk",
            tagline: "Empowering AI-assisted creativity",
            url: "https://flows.wtf/vrbs/aiartists"
        });

        // Add second-level recipients to the Artists Budget
        (, realArtistsBudget) = Flow(artistsBudget).addFlowRecipient(
            keccak256(abi.encode(realArtistsBudgetMeta)),
            realArtistsBudgetMeta,
            riderway,
            address(0),
            abi.encode(address(selfManagedFlowImpl), riderway)
        );

        (, aiArtistsBudget) = Flow(artistsBudget).addFlowRecipient(
            keccak256(abi.encode(aiArtistsBudgetMeta)),
            aiArtistsBudgetMeta,
            rocketman,
            address(0),
            abi.encode(address(selfManagedFlowImpl), rocketman)
        );

        assertEq(
            SelfManagedFlow(realArtistsBudget).allocator(),
            riderway,
            "Real Artists Budget allocator should be riderway"
        );
        assertEq(
            SelfManagedFlow(aiArtistsBudget).allocator(),
            rocketman,
            "AI Artists Budget allocator should be rocketman"
        );
    }

    // function testSelfManagedChildFlowStructure() public {
    //     // Verify the hierarchy structure
    //     assertEq(Flow(artistsBudget).parent(), address(flow), "Artists Budget parent should be main flow");
    //     assertEq(Flow(accelerator).parent(), address(flow), "Accelerator parent should be main flow");

    //     assertEq(Flow(realMadrid).parent(), accelerator, "Real Madrid parent should be Accelerator");
    //     assertEq(Flow(healthAi).parent(), accelerator, "Health AI parent should be Accelerator");

    //     assertEq(
    //         Flow(realArtistsBudget).parent(),
    //         artistsBudget,
    //         "Real Artists Budget parent should be Artists Budget"
    //     );
    //     assertEq(Flow(aiArtistsBudget).parent(), artistsBudget, "AI Artists Budget parent should be Artists Budget");
    // }

    // function testSelfManagedChildFlowImplementation() public {
    //     // Verify the implementation addresses
    //     assertEq(
    //         Flow(artistsBudget).flowImpl(),
    //         address(flowImpl),
    //         "Artists Budget should use the same implementation"
    //     );
    //     assertEq(Flow(accelerator).flowImpl(), address(flowImpl), "Accelerator should use the same implementation");
    // }
}
