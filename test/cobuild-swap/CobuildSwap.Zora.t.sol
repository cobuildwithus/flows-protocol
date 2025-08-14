// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICobuildSwap } from "../../src/experimental/interfaces/ICobuildSwap.sol";
import { CobuildSwapBaseFork_DeployProxy_Test } from "./CobuildSwap.t.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Base mainnet fork test that deploys a brand-new CobuildSwap proxy in setUp()
///         and exercises executeBatchZoraCreatorCoin via the *real* Uniswap Universal Router.
contract CobuildSwapBaseFork_Zora_Test is CobuildSwapBaseFork_DeployProxy_Test {
    // --- local helpers to reduce repetition ---
    function _singleAttr(
        address creator,
        uint256 amount,
        bytes memory data
    ) internal pure returns (ICobuildSwap.CreatorAttribution[] memory a) {
        a = new ICobuildSwap.CreatorAttribution[](1);
        a[0] = ICobuildSwap.CreatorAttribution({ creator: creator, amount: amount, data: data });
    }

    function _genUsers(string memory prefix, uint256 n) internal returns (address[] memory users) {
        users = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            users[i] = makeAddr(string.concat(prefix, vm.toString(i)));
        }
    }

    function _fundAndApproveUSDC(address[] memory users, uint256 amount) internal {
        for (uint256 i = 0; i < users.length; i++) {
            deal(USDC, users[i], amount);
            vm.prank(users[i]);
            IERC20(USDC).approve(address(cs), type(uint256).max);
        }
    }

    function _buildUniformPayees(
        address[] memory users,
        uint256 amountInPerUser,
        address attributionCreator
    ) internal pure returns (ICobuildSwap.Payee[] memory payees) {
        address[] memory recipients = new address[](users.length);
        uint256[] memory amountIns = new uint256[](users.length);
        ICobuildSwap.CreatorAttribution[][] memory attrsPerUser = new ICobuildSwap.CreatorAttribution[][](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            recipients[i] = users[i];
            amountIns[i] = amountInPerUser;
            attrsPerUser[i] = _singleAttr(attributionCreator, 1, bytes(""));
        }
        payees = _makePayees(users, recipients, amountIns, attrsPerUser);
    }

    function _poolKeyZoraCreatorA() internal view returns (PoolKey memory) {
        return
            PoolKey({
                currency0: Currency.wrap(ZORA),
                currency1: Currency.wrap(CREATOR_A),
                fee: 30000,
                tickSpacing: 200,
                hooks: IHooks(HOOKS_A)
            });
    }

    function _buildS(
        ICobuildSwap.Payee[] memory payees
    ) internal view returns (ICobuildSwap.ZoraCreatorCoinOneToMany memory s) {
        s = ICobuildSwap.ZoraCreatorCoinOneToMany({
            creator: CREATOR_A,
            key: _poolKeyZoraCreatorA(),
            v3Fee: uint24(3000),
            deadline: 175514485700,
            minZoraOut: 1,
            minCreatorOut: 1,
            payees: payees
        });
    }

    function _expectedTotalFee(
        ICobuildSwap.Payee[] memory payees,
        uint16 feeBps,
        uint256 minFeeAbs
    ) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < payees.length; i++) {
            total += _feeFor(payees[i].amountIn, feeBps, minFeeAbs);
        }
    }

    function _assertRecipientsReceived(address token, address[] memory recipients) internal view {
        for (uint256 i = 0; i < recipients.length; i++) {
            require(IERC20(token).balanceOf(recipients[i]) > 0, "recipient no out");
        }
    }

    function _runUniformZoraOneToMany(uint256 n, uint256 amountPerUser) internal {
        uint16 feeBps = cs.feeBps();
        uint256 minFeeAbs = cs.minFeeAbsolute();

        address[] memory users = _genUsers("user", n);
        _fundAndApproveUSDC(users, amountPerUser);
        ICobuildSwap.Payee[] memory payees = _buildUniformPayees(users, amountPerUser, CREATOR_A);
        ICobuildSwap.ZoraCreatorCoinOneToMany memory s = _buildS(payees);

        uint256 feeBefore = IERC20(USDC).balanceOf(FEE_COLLECTOR);
        uint256 expectedFee = _expectedTotalFee(payees, feeBps, minFeeAbs);

        vm.prank(EXECUTOR);
        cs.executeZoraCreatorCoinOneToMany(UNIVERSAL_ROUTER, s);

        uint256 feeAfter = IERC20(USDC).balanceOf(FEE_COLLECTOR);
        assertEq(feeAfter - feeBefore, expectedFee, "fee mismatch");
        _assertRecipientsReceived(CREATOR_A, users);
    }
    // ---------- One-to-many with 3 users ----------
    function test_executeZoraCreatorCoinOneToMany_threeUsers() public {
        // Pull current fee config for expectation math
        uint16 feeBps = cs.feeBps();
        uint256 minFeeAbs = cs.minFeeAbsolute();

        // Prepare three payees (USER from base + two fresh addresses)
        address user1 = USER;
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        // Fund users with USDC and approve proxy
        deal(USDC, user2, 1_000_000); // 1.0 USDC
        deal(USDC, user3, 1_000_000); // 1.0 USDC
        vm.prank(user2);
        IERC20(USDC).approve(address(cs), type(uint256).max);
        vm.prank(user3);
        IERC20(USDC).approve(address(cs), type(uint256).max);

        // Build one-to-many input targeting CREATOR_A pool using helpers
        address[] memory creators1 = new address[](2);
        creators1[0] = CREATOR_A;
        creators1[1] = user1;
        uint256[] memory amounts1 = new uint256[](2);
        amounts1[0] = 100;
        amounts1[1] = 50;
        bytes[] memory data1 = new bytes[](2);
        data1[0] = bytes("");
        data1[1] = bytes("note-user1");
        ICobuildSwap.CreatorAttribution[] memory attrs1 = _makeAttributions(creators1, amounts1, data1);

        address[] memory creators2 = new address[](1);
        creators2[0] = CREATOR_A;
        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = 42;
        bytes[] memory data2 = new bytes[](1);
        data2[0] = bytes("note-user2");
        ICobuildSwap.CreatorAttribution[] memory attrs2 = _makeAttributions(creators2, amounts2, data2);

        address[] memory creators3 = new address[](1);
        creators3[0] = CREATOR_A;
        uint256[] memory amounts3 = new uint256[](1);
        amounts3[0] = 7;
        bytes[] memory data3 = new bytes[](1);
        data3[0] = bytes("");
        ICobuildSwap.CreatorAttribution[] memory attrs3 = _makeAttributions(creators3, amounts3, data3);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;
        uint256[] memory amountIns = new uint256[](3);
        amountIns[0] = 300_000; // 0.300000 USDC
        amountIns[1] = 200_000; // 0.200000 USDC
        amountIns[2] = 100_000; // 0.100000 USDC
        ICobuildSwap.CreatorAttribution[][] memory attrsPerUser = new ICobuildSwap.CreatorAttribution[][](3);
        attrsPerUser[0] = attrs1;
        attrsPerUser[1] = attrs2;
        attrsPerUser[2] = attrs3;
        ICobuildSwap.Payee[] memory payees = _makePayees(users, recipients, amountIns, attrsPerUser);

        ICobuildSwap.ZoraCreatorCoinOneToMany memory s = ICobuildSwap.ZoraCreatorCoinOneToMany({
            creator: 0x2d1882304c9A6Fa7F987C1B41c9fD5E8CF0516e2,
            key: PoolKey({
                currency0: Currency.wrap(ZORA),
                currency1: Currency.wrap(CREATOR_A),
                fee: 30000,
                tickSpacing: 200,
                hooks: IHooks(HOOKS_A)
            }),
            v3Fee: uint24(3000),
            deadline: 175514485700,
            minZoraOut: 1,
            minCreatorOut: 1,
            payees: payees
        });

        // Snap balances for assertions
        uint256 feeBefore = IERC20(USDC).balanceOf(FEE_COLLECTOR);
        uint256 out1_before = IERC20(CREATOR_A).balanceOf(user1);
        uint256 out2_before = IERC20(CREATOR_A).balanceOf(user2);
        uint256 out3_before = IERC20(CREATOR_A).balanceOf(user3);

        // Expected total fees across all payees
        uint256 expectedFee = _feeFor(payees[0].amountIn, feeBps, minFeeAbs) +
            _feeFor(payees[1].amountIn, feeBps, minFeeAbs) +
            _feeFor(payees[2].amountIn, feeBps, minFeeAbs);

        // Execute as the configured executor (CobuildSwap.onlyExecutor)
        vm.prank(EXECUTOR);
        cs.executeZoraCreatorCoinOneToMany(UNIVERSAL_ROUTER, s);

        // --- Assertions ---
        // 1) Fees were pulled and delivered to feeCollector in USDC
        uint256 feeAfter = IERC20(USDC).balanceOf(FEE_COLLECTOR);
        assertEq(feeAfter - feeBefore, expectedFee, "feeCollector did not receive expected USDC fee");

        // 2) Each recipient received some creator token
        uint256 out1_after = IERC20(CREATOR_A).balanceOf(user1);
        uint256 out2_after = IERC20(CREATOR_A).balanceOf(user2);
        uint256 out3_after = IERC20(CREATOR_A).balanceOf(user3);
        assertGt(out1_after - out1_before, 0, "no creator token to user1");
        assertGt(out2_after - out2_before, 0, "no creator token to user2");
        assertGt(out3_after - out3_before, 0, "no creator token to user3");
    }

    // ---------- One-to-many with 100 users (each 0.1 USDC) ----------
    function test_executeZoraCreatorCoinOneToMany_hundredUsers() public {
        _runUniformZoraOneToMany(100, 100_000);
    }

    // ---------- One-to-many with 1000 users (each 0.1 USDC) ----------
    function test_executeZoraCreatorCoinOneToMany_thousandUsers() public {
        _runUniformZoraOneToMany(1000, 100_000);
    }
}
