// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICobuildSwap } from "../../src/experimental/interfaces/ICobuildSwap.sol";
import { CobuildSwapBaseFork_DeployProxy_Test } from "./CobuildSwap.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IJBTokens } from "../../src/interfaces/external/juicebox/IJBTokens.sol";

/// @notice Validation and revert-path tests for executeJuiceboxPayMany.
contract CobuildSwapBaseFork_Juicebox_Reverts_Test is CobuildSwapBaseFork_DeployProxy_Test {
    address internal PROJECT_TOKEN;

    function setUp() public override {
        super.setUp();
        PROJECT_TOKEN = address(IJBTokens(address(cs.JB_TOKENS())).tokenOf(99));
        require(PROJECT_TOKEN != address(0), "project token addr 0");
    }
    function _fundAndApproveUSDC(address[] memory users, uint256 amountPerUser) internal {
        for (uint256 i = 0; i < users.length; i++) {
            deal(USDC, users[i], amountPerUser);
            vm.prank(users[i]);
            IERC20(USDC).approve(address(cs), amountPerUser);
        }
    }

    function test_invalidV3Fee_reverts() public {
        address user1 = makeAddr("jbBadV3Fee1");
        address user2 = makeAddr("jbBadV3Fee2");
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;
        uint256[] memory amountIns = new uint256[](2);
        amountIns[0] = 100_000;
        amountIns[1] = 100_000;
        _fundAndApproveUSDC(users, 200_000);

        ICobuildSwap.Payee[] memory payees = _makePayees(users, recipients, amountIns);

        ICobuildSwap.JuiceboxPayMany memory s = ICobuildSwap.JuiceboxPayMany({
            universalRouter: UNIVERSAL_ROUTER,
            v3Fee: uint24(23232),
            deadline: 175514485700,
            projectToken: PROJECT_TOKEN,
            minEthOut: 1,
            memo: "bad v3 fee",
            metadata: bytes(""),
            payees: payees
        });

        vm.expectRevert(ICobuildSwap.INVALID_V3_FEE.selector);
        vm.prank(EXECUTOR);
        cs.executeJuiceboxPayMany(s);
    }

    function test_routerNotAllowlisted_reverts() public {
        address user1 = makeAddr("jbBadRouter1");
        address user2 = makeAddr("jbBadRouter2");
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;
        uint256[] memory amountIns = new uint256[](2);
        amountIns[0] = 50_000;
        amountIns[1] = 50_000;
        _fundAndApproveUSDC(users, 100_000);

        ICobuildSwap.Payee[] memory payees = _makePayees(users, recipients, amountIns);

        address badRouter = makeAddr("notAllowlistedRouter");

        ICobuildSwap.JuiceboxPayMany memory s = ICobuildSwap.JuiceboxPayMany({
            universalRouter: badRouter,
            v3Fee: uint24(500),
            deadline: 175514485700,
            projectToken: PROJECT_TOKEN,
            minEthOut: 1,
            memo: "bad router",
            metadata: bytes(""),
            payees: payees
        });

        vm.expectRevert(ICobuildSwap.ROUTER_NOT_ALLOWED.selector);
        vm.prank(EXECUTOR);
        cs.executeJuiceboxPayMany(s);
    }

    function test_invalidMinEthOut_reverts() public {
        address user1 = makeAddr("jbMinOut1");
        address user2 = makeAddr("jbMinOut2");
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;
        uint256[] memory amountIns = new uint256[](2);
        amountIns[0] = 100_000;
        amountIns[1] = 100_000;
        _fundAndApproveUSDC(users, 100_000);

        ICobuildSwap.Payee[] memory payees = _makePayees(users, recipients, amountIns);

        ICobuildSwap.JuiceboxPayMany memory s = ICobuildSwap.JuiceboxPayMany({
            universalRouter: UNIVERSAL_ROUTER,
            v3Fee: uint24(500),
            deadline: 175514485700,
            projectToken: PROJECT_TOKEN,
            minEthOut: 0, // invalid
            memo: "minOut zero",
            metadata: bytes(""),
            payees: payees
        });

        vm.expectRevert(ICobuildSwap.INVALID_MIN_OUT.selector);
        vm.prank(EXECUTOR);
        cs.executeJuiceboxPayMany(s);
    }

    function test_expiredDeadline_reverts() public {
        address user1 = makeAddr("jbPast1");
        address user2 = makeAddr("jbPast2");
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;
        uint256[] memory amountIns = new uint256[](2);
        amountIns[0] = 50_000;
        amountIns[1] = 50_000;
        _fundAndApproveUSDC(users, 50_000);

        ICobuildSwap.Payee[] memory payees = _makePayees(users, recipients, amountIns);

        ICobuildSwap.JuiceboxPayMany memory s = ICobuildSwap.JuiceboxPayMany({
            universalRouter: UNIVERSAL_ROUTER,
            v3Fee: uint24(500),
            deadline: block.timestamp - 1, // expired
            projectToken: PROJECT_TOKEN,
            minEthOut: 1,
            memo: "expired",
            metadata: bytes(""),
            payees: payees
        });

        vm.expectRevert(ICobuildSwap.EXPIRED_DEADLINE.selector);
        vm.prank(EXECUTOR);
        cs.executeJuiceboxPayMany(s);
    }

    function test_invalidRecipient_reverts() public {
        address user1 = makeAddr("jbBadRecip1");
        address user2 = makeAddr("jbBadRecip2");
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        address[] memory recipients = new address[](2);
        recipients[0] = address(0); // invalid
        recipients[1] = user2;
        uint256[] memory amountIns = new uint256[](2);
        amountIns[0] = 100_000;
        amountIns[1] = 100_000;
        _fundAndApproveUSDC(users, 100_000);

        ICobuildSwap.Payee[] memory payees = _makePayees(users, recipients, amountIns);

        ICobuildSwap.JuiceboxPayMany memory s = ICobuildSwap.JuiceboxPayMany({
            universalRouter: UNIVERSAL_ROUTER,
            v3Fee: uint24(500),
            deadline: 175514485700,
            projectToken: PROJECT_TOKEN,
            minEthOut: 1,
            memo: "bad recip",
            metadata: bytes(""),
            payees: payees
        });

        vm.expectRevert(ICobuildSwap.INVALID_ADDRESS.selector);
        vm.prank(EXECUTOR);
        cs.executeJuiceboxPayMany(s);
    }
}
