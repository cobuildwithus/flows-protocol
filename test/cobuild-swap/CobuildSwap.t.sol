// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { CobuildSwap } from "../../src/experimental/CobuildSwap.sol";
import { ICobuildSwap } from "../../src/experimental/interfaces/ICobuildSwap.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @notice Base mainnet fork test that deploys a brand-new CobuildSwap proxy in setUp()
///         and exercises executeBatchZoraCreatorCoin via the *real* Uniswap Universal Router.
contract CobuildSwapBaseFork_DeployProxy_Test is Test {
    // ---------- Chain fork ----------
    function setUp() public {
        // Configure an RPC endpoint named "base" in foundry.toml:
        // [rpc_endpoints]
        // base = "${BASE_RPC_URL}"
        vm.createSelectFork(vm.rpcUrl("base"));

        // ---- fresh deploy of CobuildSwap (impl + proxy) ----
        _deployFreshProxy();
        _primeUserFundsAndApprovals();
    }

    // ---------- Known prod addresses on Base ----------
    // Universal Router (Base)
    address constant UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43; // Uniswap Universal Router v2 on Base. :contentReference[oaicite:1]{index=1}
    // USDC (native on Base)
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // Circle USDC on Base. :contentReference[oaicite:2]{index=2}
    // ZORA token (Base)
    address constant ZORA = 0x1111111111166b7FE7bd91427724B487980aFc69; // ZORA on Base. :contentReference[oaicite:3]{index=3}

    // You provided these creator/hook/pool params in your example (kept verbatim).
    address constant CREATOR_A = 0x774E70664b22764d0225C52bc87b7b621FCB6D04;
    address constant HOOKS_A = 0x5e5D19d22c85A4aef7C1FdF25fB22A5a38f71040;

    address constant CREATOR_B = 0x88eB1787620f3c82FBd962cFD08c72e4604F4779;
    address constant HOOKS_B = 0xd61A675F8a0c67A73DC3B54FB7318B4D91409040;

    // ---------- Test actors ----------
    address internal EXECUTOR = makeAddr("executor");
    address internal FEE_COLLECTOR = makeAddr("feeCollector");
    address internal USER = 0xF5179fCf14F5c233689B0b4E9B7B03785Ecba5a5; // from your example

    // ---------- System under test (freshly deployed) ----------
    CobuildSwap internal cs;

    // ---------- Deploy a new proxy (no reliance on prod deployment) ----------
    function _deployFreshProxy() internal {
        // configure fee params
        uint16 feeBps = 200; // 2%
        uint256 minFeeAbs = 0; // keep simple; adjust if you want a floor

        // deploy implementation
        CobuildSwap impl = new CobuildSwap();

        // prepare initializer calldata, mirroring your DeployScript
        bytes memory initData = abi.encodeCall(
            CobuildSwap.initialize,
            (USDC, ZORA, UNIVERSAL_ROUTER, EXECUTOR, FEE_COLLECTOR, feeBps, minFeeAbs)
        );

        // deploy proxy initialized with initData (owner becomes this test contract)
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        cs = CobuildSwap(payable(address(proxy)));

        // Sanity checks: router is allowed, owner is this test, parameters wired
        assertTrue(cs.allowedRouters(UNIVERSAL_ROUTER), "UR not allowlisted");
        assertEq(cs.owner(), address(this), "owner != test contract");
        assertEq(address(cs.USDC()), USDC, "USDC mismatch");
        assertEq(address(cs.ZORA()), ZORA, "ZORA mismatch");
        assertEq(cs.executor(), EXECUTOR, "executor mismatch");
        assertEq(cs.feeCollector(), FEE_COLLECTOR, "feeCollector mismatch");
    }

    // ---------- Fund user + approvals on the fork ----------
    function _primeUserFundsAndApprovals() internal {
        // Give the on-chain USER 10 USDC on the fork; approve the *fresh* proxy
        deal(USDC, USER, 10_000_000); // 10 * 1e6
        vm.prank(USER);
        IERC20(USDC).approve(address(cs), type(uint256).max);
    }

    // ---------- helpers ----------
    function _feeFor(uint256 amountInUSDC, uint16 feeBps, uint256 minFeeAbs) internal pure returns (uint256) {
        uint256 pct = (amountInUSDC * feeBps) / 10_000;
        return pct >= minFeeAbs ? pct : minFeeAbs;
    }

    function _makePayee(address user, uint256 amountIn) internal pure returns (ICobuildSwap.Payee memory) {
        return ICobuildSwap.Payee({ user: user, recipient: user, amountIn: amountIn });
    }

    function _makePayeeWithRecipient(
        address user,
        address recipient,
        uint256 amountIn
    ) internal pure returns (ICobuildSwap.Payee memory) {
        return ICobuildSwap.Payee({ user: user, recipient: recipient, amountIn: amountIn });
    }

    function _makePayees(
        address[] memory users,
        address[] memory recipients,
        uint256[] memory amountIns
    ) internal pure returns (ICobuildSwap.Payee[] memory payees) {
        uint256 n = users.length;
        require(recipients.length == n && amountIns.length == n, "length mismatch");
        payees = new ICobuildSwap.Payee[](n);
        for (uint256 i = 0; i < n; i++) {
            payees[i] = ICobuildSwap.Payee({ user: users[i], recipient: recipients[i], amountIn: amountIns[i] });
        }
    }
}
