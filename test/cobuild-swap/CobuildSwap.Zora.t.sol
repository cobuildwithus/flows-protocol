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
        uint256 amountInPerUser,
        address attributionCreator
    ) internal pure returns (ICobuildSwap.Payee[] memory payees) {
        address[] memory recipients = new address[](users.length);
        uint256[] memory amountIns = new uint256[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            recipients[i] = users[i];
            amountIns[i] = amountInPerUser;
        }
        payees = _makePayees(users, recipients, amountIns);
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
        uint256 gross;
        for (uint256 i = 0; i < payees.length; i++) {
            gross += payees[i].amountIn;
        }
        total = _feeFor(gross, feeBps, minFeeAbs);
    }

    function _assertRecipientsReceived(address token, address[] memory recipients) internal view {
        for (uint256 i = 0; i < recipients.length; i++) {
            require(IERC20(token).balanceOf(recipients[i]) > 0, "recipient no out");
        }
    }

    function _runUniformZoraOneToMany(uint256 n, uint256 amountPerUser) internal {
        vm.pauseGasMetering();

        uint16 feeBps = cs.feeBps();
        uint256 minFeeAbs = cs.minFeeAbsolute();

        address[] memory users = _genUsers("user", n);
        _fundAndApproveUSDC(users, amountPerUser);
        ICobuildSwap.Payee[] memory payees = _buildUniformPayees(users, amountPerUser, CREATOR_A);
        ICobuildSwap.ZoraCreatorCoinOneToMany memory s = _buildS(payees);

        uint256 feeBefore = IERC20(USDC).balanceOf(FEE_COLLECTOR);
        uint256 expectedFee = _expectedTotalFee(payees, feeBps, minFeeAbs);

        vm.resumeGasMetering();

        vm.prank(EXECUTOR);
        cs.executeZoraCreatorCoinOneToMany(UNIVERSAL_ROUTER, s);

        vm.pauseGasMetering();

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

        address[] memory creators2 = new address[](1);
        creators2[0] = CREATOR_A;
        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = 42;
        bytes[] memory data2 = new bytes[](1);
        data2[0] = bytes("note-user2");

        address[] memory creators3 = new address[](1);
        creators3[0] = CREATOR_A;
        uint256[] memory amounts3 = new uint256[](1);
        amounts3[0] = 7;
        bytes[] memory data3 = new bytes[](1);
        data3[0] = bytes("");

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
        ICobuildSwap.Payee[] memory payees = _makePayees(users, recipients, amountIns);

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
        uint256 expectedFee = _feeFor(amountIns[0] + amountIns[1] + amountIns[2], feeBps, minFeeAbs);

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
        // revert("FORCE_GAS_LOGS");
    }

    // ---------- Fee handling: floor applied once per batch ----------
    function test_feeFloorAppliedOnce_perBatch() public {
        // Configure: 0% BPS, non-zero absolute floor
        vm.prank(address(this));
        cs.setFeeBps(0);
        vm.prank(address(this));
        cs.setMinFeeAbsolute(50_000); // $0.05 with 6d USDC

        // Build 3 payees (each 0.03 USDC) so totalGross (0.09) > floor (0.05)
        address[] memory users = _genUsers("floorUser", 3);
        _fundAndApproveUSDC(users, 30_000);
        ICobuildSwap.Payee[] memory payees = _buildUniformPayees(users, 30_000, CREATOR_A);
        ICobuildSwap.ZoraCreatorCoinOneToMany memory s = _buildS(payees);

        uint256 feeBefore = IERC20(USDC).balanceOf(FEE_COLLECTOR);

        vm.prank(EXECUTOR);
        cs.executeZoraCreatorCoinOneToMany(UNIVERSAL_ROUTER, s);

        uint256 feeAfter = IERC20(USDC).balanceOf(FEE_COLLECTOR);
        // Expect exactly one floor fee (not N * floor)
        assertEq(feeAfter - feeBefore, 50_000, "batch floor not applied once");
    }

    // ---------- Fee handling: percentage dominates floor when large ----------
    function test_feePercentageDominates_overFloor() public {
        // Configure: 2% BPS, small absolute floor
        vm.prank(address(this));
        cs.setFeeBps(200); // 2%
        vm.prank(address(this));
        cs.setMinFeeAbsolute(1_000); // $0.001

        // Build 2 large payees (each 2 USDC)
        address[] memory users = _genUsers("pctUser", 2);
        _fundAndApproveUSDC(users, 2_000_000);
        ICobuildSwap.Payee[] memory payees = _buildUniformPayees(users, 2_000_000, CREATOR_A);
        ICobuildSwap.ZoraCreatorCoinOneToMany memory s = _buildS(payees);

        uint256 totalGross = 2 * 2_000_000;
        uint256 expectedFee = _feeFor(totalGross, 200, 1_000); // 4,000,000 * 2% = 80,000 > floor

        uint256 feeBefore = IERC20(USDC).balanceOf(FEE_COLLECTOR);

        vm.prank(EXECUTOR);
        cs.executeZoraCreatorCoinOneToMany(UNIVERSAL_ROUTER, s);

        uint256 feeAfter = IERC20(USDC).balanceOf(FEE_COLLECTOR);
        assertEq(feeAfter - feeBefore, expectedFee, "percentage fee should dominate floor");
    }

    // ---------- Fee handling: updating feeBps changes charged fee ----------
    function test_feeBpsUpdate_takesEffect() public {
        // Start with 1% then update to 3%
        vm.prank(address(this));
        cs.setFeeBps(100);
        vm.prank(address(this));
        cs.setMinFeeAbsolute(0);

        address[] memory users = _genUsers("bpsUser", 2);
        _fundAndApproveUSDC(users, 500_000);
        ICobuildSwap.Payee[] memory payees = _buildUniformPayees(users, 500_000, CREATOR_A); // total 1.0 USDC
        ICobuildSwap.ZoraCreatorCoinOneToMany memory s = _buildS(payees);

        // Run at 1%
        uint256 feeBefore1 = IERC20(USDC).balanceOf(FEE_COLLECTOR);
        vm.prank(EXECUTOR);
        cs.executeZoraCreatorCoinOneToMany(UNIVERSAL_ROUTER, s);
        uint256 feeAfter1 = IERC20(USDC).balanceOf(FEE_COLLECTOR);
        assertEq(feeAfter1 - feeBefore1, _feeFor(1_000_000, 100, 0), "fee mismatch at 1%");

        // Update to 3% and run again (re-fund users for the second batch)
        vm.prank(address(this));
        cs.setFeeBps(300);
        _fundAndApproveUSDC(users, 500_000);
        uint256 feeBefore2 = IERC20(USDC).balanceOf(FEE_COLLECTOR);
        vm.prank(EXECUTOR);
        cs.executeZoraCreatorCoinOneToMany(UNIVERSAL_ROUTER, s);
        uint256 feeAfter2 = IERC20(USDC).balanceOf(FEE_COLLECTOR);
        assertEq(feeAfter2 - feeBefore2, _feeFor(1_000_000, 300, 0), "fee mismatch at 3%");
    }

    // // ---------- One-to-many with 1000 users (each 0.1 USDC) ----------
    // function test_executeZoraCreatorCoinOneToMany_thousandUsers() public {
    //     _runUniformZoraOneToMany(500, 100_000);
    // }
}
