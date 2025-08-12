// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";

import { ICobuildSwap } from "./interfaces/ICobuildSwap.sol";

// ---------------------------
// Minimal external interfaces
// ---------------------------

// Permit2 (minimal)
interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

// Universal Router (minimal)
interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

// ---------------------------
// Main contract
// ---------------------------

contract CobuildSwap is Ownable2StepUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable, ICobuildSwap {
    using SafeERC20 for IERC20;

    // ---- config ----
    IERC20 public USDC; // base token
    IPermit2 public PERMIT2; // 0x000000000022D473030F116dDEE9F6B43aC78BA3 (chain-agnostic Permit2)

    address public executor;
    address public feeCollector;
    uint16 public feeBps; // e.g., 200 = 2%

    // ---- constants ----
    uint256 private constant _MAX_BPS = 10_000;

    // Universal Router: command & v4 action constants (verify against your linked periphery)
    uint8 private constant CMD_V4_SWAP = 0x10;
    uint8 private constant ACT_SWAP_EXACT_IN_SINGLE = 0x06;
    uint8 private constant ACT_SETTLE = 0x0b; // unused here
    uint8 private constant ACT_SETTLE_ALL = 0x0c;
    uint8 private constant ACT_TAKE = 0x0e; // unused here
    uint8 private constant ACT_TAKE_ALL = 0x0f;

    // ---- allowlists ----
    mapping(address => bool) public allowedRouters; // e.g., Universal Router, 0x router
    mapping(address => bool) public allowedSpenders; // e.g., 0x v2 AllowanceHolder / Permit2

    // ---- modifiers ----
    modifier onlyExecutor() {
        if (msg.sender != executor) revert NOT_EXECUTOR();
        _;
    }

    // ---- ctor / initializer ----
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _usdc,
        address _universalRouter,
        address _executor,
        address _feeCollector,
        uint16 _feeBps
    ) external initializer {
        if (
            _usdc == address(0) ||
            _universalRouter == address(0) ||
            _executor == address(0) ||
            _feeCollector == address(0)
        ) {
            revert ZERO_ADDR();
        }
        if (_feeBps > 500) revert FEE_TOO_HIGH(); // hard cap 5%

        // Init upgradeable mixins
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __Ownable2Step_init();

        _transferOwnership(msg.sender);

        USDC = IERC20(_usdc);
        executor = _executor;
        feeCollector = _feeCollector;
        feeBps = _feeBps;

        // Permit2 address (canonical across major chains)
        PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

        // One-time infinite approval from THIS contract to Permit2
        USDC.safeApprove(address(PERMIT2), type(uint256).max);

        // Allow Universal Router by default
        allowedRouters[_universalRouter] = true;
        emit RouterAllowed(_universalRouter, true);
    }

    // accept stray ETH (e.g., if a router unwraps WETH->ETH to us by mistake)
    receive() external payable {}

    // ---- admin ----
    function setExecutor(address e) external onlyOwner {
        if (e == address(0)) revert ZERO_ADDR();
        emit ExecutorChanged(executor, e);
        executor = e;
    }

    function setFeeBps(uint16 bps) external onlyOwner {
        if (bps > 500) revert FEE_TOO_HIGH();
        feeBps = bps;
        emit FeeParamsChanged(bps, feeCollector);
    }

    function setFeeCollector(address c) external onlyOwner {
        if (c == address(0)) revert ZERO_ADDR();
        feeCollector = c;
        emit FeeParamsChanged(feeBps, c);
    }

    function setRouterAllowed(address r, bool allowed) external onlyOwner {
        allowedRouters[r] = allowed;
        emit RouterAllowed(r, allowed);
    }

    event SpenderAllowed(address spender, bool allowed);

    function setSpenderAllowed(address s, bool allowed) external onlyOwner {
        allowedSpenders[s] = allowed;
        emit SpenderAllowed(s, allowed);
    }

    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    function rescueETH(address payable to, uint256 amount) external onlyOwner {
        (bool ok, ) = to.call{ value: amount }("");
        if (!ok) revert ETH_TRANSFER_FAIL();
    }

    // ---------------------------
    // Universal Router (v4 single-pool) lane
    // ---------------------------
    function executeBatchUniV4Single(
        address universalRouter,
        V4SingleSwap[] calldata swaps
    ) external override nonReentrant onlyExecutor returns (uint256[] memory amountsOut) {
        if (universalRouter == address(0) || !allowedRouters[universalRouter]) revert ROUTER_NOT_ALLOWED();

        uint256 len = swaps.length;
        if (len == 0 || len > 500) revert BAD_BATCH_SIZE();

        amountsOut = new uint256[](len);

        uint256 totalNet;
        uint256 maxDeadline;

        // Pass 1: validate & aggregate (compute nets from declared amounts for batch Permit2 allowance)
        for (uint256 i; i < len; ) {
            V4SingleSwap calldata s = swaps[i];

            if (s.user == address(0) || s.recipient == address(0)) revert INVALID_ADDRESS();
            if (s.amountIn == 0 || s.minAmountOut == 0) revert INVALID_AMOUNTS();
            if (s.deadline < block.timestamp) revert EXPIRED_DEADLINE();

            // ensure pool includes USDC and direction is USDC -> token
            address c0 = Currency.unwrap(s.key.currency0);
            address c1 = Currency.unwrap(s.key.currency1);
            bool c0IsUSDC = (c0 == address(USDC));
            bool c1IsUSDC = (c1 == address(USDC));
            if (!(c0IsUSDC || c1IsUSDC)) revert PATH_IN_MISMATCH();

            // Direction must be from the USDC side
            if (c0IsUSDC && !s.zeroForOne) revert PATH_IN_MISMATCH();
            if (c1IsUSDC && s.zeroForOne) revert PATH_IN_MISMATCH();

            uint256 fee = (uint256(s.amountIn) * feeBps) / _MAX_BPS;
            uint256 net = uint256(s.amountIn) - fee;
            if (net == 0) revert NET_AMOUNT_ZERO();

            totalNet += net;
            if (s.deadline > maxDeadline) maxDeadline = s.deadline;

            unchecked {
                ++i;
            }
        }

        // Batch-scoped Permit2 approval for UR to pull the NET USDC from THIS contract.
        if (totalNet > type(uint160).max) revert INVALID_AMOUNTS();
        uint48 expiry = maxDeadline > type(uint48).max ? type(uint48).max : uint48(maxDeadline);
        PERMIT2.approve(address(USDC), universalRouter, uint160(totalNet), expiry);

        // Pass 2: pull USDC from users (FoT-safe), take fee, then swap via UR
        for (uint256 i; i < len; ) {
            V4SingleSwap calldata s = swaps[i];

            // Pull gross from user and verify FoT is not applied
            uint256 usdcBefore = USDC.balanceOf(address(this));
            USDC.safeTransferFrom(s.user, address(this), s.amountIn);
            uint256 received = USDC.balanceOf(address(this)) - usdcBefore;
            if (received != s.amountIn) revert INVALID_AMOUNTS(); // FoT base token not supported

            // Fee -> collector, compute net
            uint256 fee = (received * feeBps) / _MAX_BPS;
            uint256 net = received - fee;
            if (fee > 0) USDC.safeTransfer(feeCollector, fee);

            // guard uint128 downcast for v4 param
            if (net > type(uint128).max) revert INVALID_AMOUNTS();

            // currencies
            Currency inCur = s.zeroForOne ? s.key.currency0 : s.key.currency1; // must be USDC side
            Currency outCur = s.zeroForOne ? s.key.currency1 : s.key.currency0;

            // forbid native (ETH) out to avoid IERC20(0) calls here
            address tokenOutAddr = Currency.unwrap(outCur);
            if (tokenOutAddr == address(0)) revert INVALID_TOKEN_OUT();

            // Build UR payload: SWAP_EXACT_IN_SINGLE -> SETTLE_ALL -> TAKE (full credit to recipient)
            bytes memory commands = abi.encodePacked(uint8(CMD_V4_SWAP));
            bytes memory actions = abi.encodePacked(
                uint8(ACT_SWAP_EXACT_IN_SINGLE),
                uint8(ACT_SETTLE_ALL),
                uint8(ACT_TAKE)
            );

            bytes[] memory params = new bytes[](3);

            // [0] SWAP_EXACT_IN_SINGLE - rely on router's slippage protection
            params[0] = abi.encode(
                IV4Router.ExactInputSingleParams({
                    poolKey: s.key,
                    zeroForOne: s.zeroForOne,
                    amountIn: uint128(net),
                    amountOutMinimum: s.minAmountOut,
                    hookData: bytes("")
                })
            );

            // [1] SETTLE_ALL(currencyIn, maxAmount)
            params[1] = abi.encode(inCur, uint256(net));

            // [2] TAKE(currencyOut, recipient, OPEN_DELTA)
            params[2] = abi.encode(outCur, s.recipient, uint256(0)); // OPEN_DELTA sentinel

            bytes[] memory inputs = new bytes[](1);
            inputs[0] = abi.encode(actions, params);

            // measure recipient diff for output tracking
            uint256 beforeBal = IERC20(tokenOutAddr).balanceOf(s.recipient);
            IUniversalRouter(universalRouter).execute(commands, inputs, s.deadline);
            uint256 afterBal = IERC20(tokenOutAddr).balanceOf(s.recipient);
            uint256 out = afterBal > beforeBal ? (afterBal - beforeBal) : 0;

            amountsOut[i] = out;

            emit SwapExecuted(s.user, s.recipient, tokenOutAddr, address(USDC), s.amountIn, fee, out, universalRouter);

            unchecked {
                ++i;
            }
        }

        // Optional: revoke UR's batch Permit2 allowance immediately:
        PERMIT2.approve(address(USDC), universalRouter, 0, 0);
    }

    // ---------------------------
    // 0x Swap API (router adapter) lane
    // ---------------------------

    function executeBatch0x(
        address expectedRouter, // 0x router entrypoint; must be allowlisted
        OxSwap[] calldata swaps
    ) external override nonReentrant onlyExecutor returns (uint256[] memory amountsOut) {
        if (expectedRouter == address(0) || !allowedRouters[expectedRouter]) revert ROUTER_NOT_ALLOWED();

        uint256 len = swaps.length;
        if (len == 0 || len > 500) revert BAD_BATCH_SIZE();

        // First pass: validate & compute per-spender summed nets for single approval each
        address[] memory spenders = new address[](len);
        uint256[] memory sums = new uint256[](len);
        uint256 uniq;

        for (uint256 i; i < len; ) {
            OxSwap calldata s = swaps[i];

            if (s.user == address(0) || s.recipient == address(0)) revert INVALID_ADDRESS();
            if (s.tokenOut == address(0)) revert INVALID_TOKEN_OUT();
            if (s.amountIn == 0 || s.minAmountOut == 0) revert INVALID_AMOUNTS();
            if (s.deadline < block.timestamp) revert EXPIRED_DEADLINE();
            if (s.callTarget != expectedRouter) revert ROUTER_NOT_ALLOWED();
            if (!allowedSpenders[s.spender]) revert SPENDER_NOT_ALLOWED();

            uint256 fee = (s.amountIn * feeBps) / _MAX_BPS;
            uint256 net = s.amountIn - fee;
            if (net == 0) revert NET_AMOUNT_ZERO();

            bool found;
            for (uint256 j; j < uniq; ++j) {
                if (spenders[j] == s.spender) {
                    sums[j] += net;
                    found = true;
                    break;
                }
            }
            if (!found) {
                spenders[uniq] = s.spender;
                sums[uniq] = net;
                ++uniq;
            }

            unchecked {
                ++i;
            }
        }

        // Approve each spender once for its total net (zero-then-set pattern)
        for (uint256 j; j < uniq; ++j) {
            USDC.safeApprove(spenders[j], 0);
            if (sums[j] > 0) USDC.safeApprove(spenders[j], sums[j]);
        }

        amountsOut = new uint256[](len);

        // Second pass: pull funds & execute swaps with per-swap accounting
        for (uint256 i; i < len; ) {
            OxSwap calldata s = swaps[i];

            // forbid sending ETH value in USDC-in swaps
            if (s.value != 0) revert INVALID_AMOUNTS();

            // Pull USDC from user and verify FoT is not applied
            uint256 preIn = USDC.balanceOf(address(this));
            USDC.safeTransferFrom(s.user, address(this), s.amountIn);
            uint256 received = USDC.balanceOf(address(this)) - preIn;
            if (received != s.amountIn) revert INVALID_AMOUNTS(); // FoT base token not supported

            // Fee -> collector (on actual received), compute net
            uint256 fee = (received * feeBps) / _MAX_BPS;
            uint256 net = received - fee;
            if (fee > 0) USDC.safeTransfer(feeCollector, fee);

            // Record balances for exact-input enforcement and FoT-safe out measurement
            uint256 usdcBeforeSpend = USDC.balanceOf(address(this));
            IERC20 out = IERC20(s.tokenOut);
            uint256 beforeRecipient = out.balanceOf(s.recipient);
            uint256 beforeSelfOut = out.balanceOf(address(this));

            // Execute 0x call
            (bool ok, bytes memory ret) = s.callTarget.call{ value: s.value }(s.callData);
            if (!ok) {
                // bubble revert reason
                assembly {
                    revert(add(ret, 32), mload(ret))
                }
            }

            // Enforce exact-input (or refund if price improved)
            uint256 usdcAfterSpend = USDC.balanceOf(address(this));
            if (usdcBeforeSpend < usdcAfterSpend) revert USDC_BALANCE_INCREASED();
            uint256 spent = usdcBeforeSpend - usdcAfterSpend;
            if (spent > net) revert INVALID_AMOUNTS(); // overspent vs intended net
            if (spent < net) USDC.safeTransfer(s.user, net - spent); // refund unspent USDC immediately

            // If router paid to us, forward only what arrived in THIS call
            uint256 afterSelfOut = out.balanceOf(address(this));
            uint256 deltaSelfOut = afterSelfOut > beforeSelfOut ? (afterSelfOut - beforeSelfOut) : 0;
            if (deltaSelfOut > 0) {
                out.safeTransfer(s.recipient, deltaSelfOut);
            }

            // Final slippage check AFTER any forward; saturating diff for safety
            uint256 afterRecipient = out.balanceOf(s.recipient);
            uint256 outAmt = afterRecipient > beforeRecipient ? (afterRecipient - beforeRecipient) : 0;
            if (outAmt < s.minAmountOut) revert SLIPPAGE();

            amountsOut[i] = outAmt;

            emit SwapExecuted(s.user, s.recipient, s.tokenOut, address(USDC), s.amountIn, fee, outAmt, s.callTarget);

            unchecked {
                ++i;
            }
        }

        // Clear approvals (defense-in-depth)
        for (uint256 j; j < uniq; ++j) {
            USDC.safeApprove(spenders[j], 0);
        }
    }

    // ---- UUPS ----
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
