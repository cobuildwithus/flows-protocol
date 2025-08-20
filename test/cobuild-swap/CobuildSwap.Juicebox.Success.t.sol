// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICobuildSwap } from "../../src/experimental/interfaces/ICobuildSwap.sol";
import { CobuildSwapBaseFork_DeployProxy_Test } from "./CobuildSwap.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IJBTokens } from "../../src/interfaces/external/juicebox/IJBTokens.sol";

/// @notice Success-path tests for executeJuiceboxPayMany using the real Universal Router.
contract CobuildSwapBaseFork_Juicebox_Success_Test is CobuildSwapBaseFork_DeployProxy_Test {
    function _fundAndApproveUSDC(address[] memory users, uint256 amountPerUser) internal {
        for (uint256 i = 0; i < users.length; i++) {
            deal(USDC, users[i], amountPerUser);
            vm.prank(users[i]);
            IERC20(USDC).approve(address(cs), amountPerUser);
        }
    }

    function test_executeJuiceboxPayMany_twoPayees() public {
        // --- Prepare two users ---
        address user1 = makeAddr("jbUser1");
        address user2 = makeAddr("jbUser2");

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        uint256[] memory amountIns = new uint256[](2);
        amountIns[0] = 500_000; // 0.5 USDC
        amountIns[1] = 300_000; // 0.3 USDC

        _fundAndApproveUSDC(users, 1_000_000);

        ICobuildSwap.Payee[] memory payees = _makePayees(users, recipients, amountIns);

        // Build Juicebox route input
        ICobuildSwap.JuiceboxPayMany memory s = ICobuildSwap.JuiceboxPayMany({
            universalRouter: UNIVERSAL_ROUTER,
            v3Fee: uint24(500),
            deadline: 175514485700,
            projectId: 99,
            minEthOut: 1,
            memo: "jb route test",
            metadata: bytes(""),
            payees: payees
        });

        // Discover project token and snapshot pre-balances
        address projectToken = address(IJBTokens(address(cs.JB_TOKENS())).tokenOf(s.projectId));
        require(projectToken != address(0), "project token addr 0");

        uint256 bal1Before = IERC20(projectToken).balanceOf(user1);
        uint256 bal2Before = IERC20(projectToken).balanceOf(user2);

        // Execute as configured executor
        vm.prank(EXECUTOR);
        cs.executeJuiceboxPayMany(s);

        // Assert recipients received project tokens
        uint256 bal1After = IERC20(projectToken).balanceOf(user1);
        uint256 bal2After = IERC20(projectToken).balanceOf(user2);
        assertGt(bal1After - bal1Before, 0, "user1 no JB token");
        assertGt(bal2After - bal2Before, 0, "user2 no JB token");
    }

    function test_feeTransferred_toCollector_twoPayees() public {
        // users and payees
        address user1 = makeAddr("jbFeeUser1");
        address user2 = makeAddr("jbFeeUser2");
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;
        uint256[] memory amountIns = new uint256[](2);
        amountIns[0] = 400_000; // 0.4
        amountIns[1] = 600_000; // 0.6
        _fundAndApproveUSDC(users, 1_000_000);

        ICobuildSwap.Payee[] memory payees = _makePayees(users, recipients, amountIns);

        ICobuildSwap.JuiceboxPayMany memory s = ICobuildSwap.JuiceboxPayMany({
            universalRouter: UNIVERSAL_ROUTER,
            v3Fee: uint24(500),
            deadline: 175514485700,
            projectId: 99,
            minEthOut: 1,
            memo: "jb fee test",
            metadata: bytes(""),
            payees: payees
        });

        uint16 feeBps = cs.feeBps();
        uint256 minFeeAbs = cs.minFeeAbsolute();
        uint256 totalGross = amountIns[0] + amountIns[1];
        uint256 expectedFee = _feeFor(totalGross, feeBps, minFeeAbs);
        uint256 feeBefore = IERC20(USDC).balanceOf(FEE_COLLECTOR);

        vm.prank(EXECUTOR);
        cs.executeJuiceboxPayMany(s);

        uint256 feeAfter = IERC20(USDC).balanceOf(FEE_COLLECTOR);
        assertEq(feeAfter - feeBefore, expectedFee, "feeCollector USDC mismatch");
    }
}
