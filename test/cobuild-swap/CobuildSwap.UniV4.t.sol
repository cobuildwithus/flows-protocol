// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICobuildSwap } from "../../src/experimental/interfaces/ICobuildSwap.sol";
import { CobuildSwapBaseFork_DeployProxy_Test } from "./CobuildSwap.t.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CobuildSwap_UniV4_Test is CobuildSwapBaseFork_DeployProxy_Test {
    function _genUsers(string memory prefix, uint256 n) internal returns (address[] memory users) {
        users = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            users[i] = makeAddr(string.concat(prefix, vm.toString(i)));
        }
    }

    function _fundAndApproveUSDC(address[] memory users, uint256 amount) internal {
        for (uint256 i = 0; i < users.length; i++) {
            deal(USDC, users[i], amount * 2);
            vm.prank(users[i]);
            IERC20(USDC).approve(address(cs), amount);
        }
    }

    function _buildUniformPayees(
        address[] memory users,
        uint256 amountInPerUser
    ) internal pure returns (ICobuildSwap.Payee[] memory payees) {
        address[] memory recipients = new address[](users.length);
        uint256[] memory amountIns = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            recipients[i] = users[i];
            amountIns[i] = amountInPerUser;
        }
        payees = _makePayees(users, recipients, amountIns);
    }

    function _poolKeyUSDCZora() internal pure returns (PoolKey memory) {
        return
            PoolKey({
                // Sorted by address per v4 requirements: ZORA < USDC
                currency0: Currency.wrap(USDC), // ZORA
                currency1: Currency.wrap(ZORA), // USDC
                fee: 3000, // 0.30%
                tickSpacing: 60, // standard for 0.30%
                hooks: IHooks(address(0))
            });
    }

    function _expectedTotalFee(
        ICobuildSwap.Payee[] memory payees,
        uint16 feeBps,
        uint256 minFeeAbs
    ) internal pure returns (uint256 total) {
        uint256 gross;
        for (uint256 i = 0; i < payees.length; i++) {
            gross += payees[i].amountIn;
        }
        total = _feeFor(gross, feeBps, minFeeAbs);
    }

    function test_executeBatchUniV4Single_threeUsers_USDCToZora() public {
        uint16 feeBps = cs.feeBps();
        uint256 minFeeAbs = cs.minFeeAbsolute();

        address user1 = USER;
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        deal(USDC, user2, 1_000_000);
        deal(USDC, user3, 1_000_000);
        vm.prank(user2);
        IERC20(USDC).approve(address(cs), type(uint256).max);
        vm.prank(user3);
        IERC20(USDC).approve(address(cs), type(uint256).max);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;
        uint256[] memory amountIns = new uint256[](3);
        amountIns[0] = 300_000;
        amountIns[1] = 200_000;
        amountIns[2] = 100_000;
        ICobuildSwap.Payee[] memory payees = _makePayees(users, recipients, amountIns);

        ICobuildSwap.V4SingleOneToMany memory s = ICobuildSwap.V4SingleOneToMany({
            creator: address(0xC0FFEE),
            key: _poolKeyUSDCZora(),
            zeroForOne: true,
            minAmountOut: uint128(1),
            deadline: 175514485700,
            payees: payees
        });

        uint256 feeBefore = IERC20(USDC).balanceOf(FEE_COLLECTOR);
        uint256 expectedFee = _expectedTotalFee(payees, feeBps, minFeeAbs);

        uint256 zoraBefore1 = IERC20(ZORA).balanceOf(user1);
        uint256 zoraBefore2 = IERC20(ZORA).balanceOf(user2);
        uint256 zoraBefore3 = IERC20(ZORA).balanceOf(user3);

        vm.prank(EXECUTOR);
        cs.executeBatchUniV4Single(UNIVERSAL_ROUTER, s);

        uint256 feeAfter = IERC20(USDC).balanceOf(FEE_COLLECTOR);
        assertEq(feeAfter - feeBefore, expectedFee, "fee mismatch");

        uint256 zoraAfter1 = IERC20(ZORA).balanceOf(user1);
        uint256 zoraAfter2 = IERC20(ZORA).balanceOf(user2);
        uint256 zoraAfter3 = IERC20(ZORA).balanceOf(user3);
        assertGt(zoraAfter1 - zoraBefore1, 0, "no ZORA to user1");
        assertGt(zoraAfter2 - zoraBefore2, 0, "no ZORA to user2");
        assertGt(zoraAfter3 - zoraBefore3, 0, "no ZORA to user3");
    }

    function test_executeBatchUniV4Single_hundredUsers_USDCToZora() public {
        address[] memory users = _genUsers("uniV4User", 100);
        _fundAndApproveUSDC(users, 100_000);
        ICobuildSwap.Payee[] memory payees = _buildUniformPayees(users, 100_000);

        ICobuildSwap.V4SingleOneToMany memory s = ICobuildSwap.V4SingleOneToMany({
            creator: address(0xC0FFEE),
            key: _poolKeyUSDCZora(),
            zeroForOne: true,
            minAmountOut: uint128(1),
            deadline: 175514485700,
            payees: payees
        });

        vm.prank(EXECUTOR);
        cs.executeBatchUniV4Single(UNIVERSAL_ROUTER, s);
        // Basic smoke test: ensure some ZORA arrived to someone
        bool anyReceived;
        for (uint256 i = 0; i < users.length; i++) {
            if (IERC20(ZORA).balanceOf(users[i]) > 0) {
                anyReceived = true;
                break;
            }
        }
        assertTrue(anyReceived, "no ZORA received by any user");
    }
}
