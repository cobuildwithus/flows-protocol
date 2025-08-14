// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

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
    IERC20 public ZORA; // ZORA token
    IPermit2 public PERMIT2; // 0x000000000022D473030F116dDEE9F6B43aC78BA3

    address public executor;
    address public feeCollector;
    uint16 public feeBps; // e.g., 200 = 2%

    // Absolute per-trade fee floor, denominated in USDC/base token units
    uint256 public minFeeAbsolute;

    // ---- constants ----
    uint256 private constant _MAX_BPS = 10_000;

    // Universal Router: command & v4 action constants
    uint8 private constant CMD_V4_SWAP = 0x10;
    uint8 private constant CMD_V3_SWAP_EXACT_IN = 0x00; // <— NEW (v3 hop)
    uint8 private constant ACT_SWAP_EXACT_IN_SINGLE = 0x06;
    uint8 private constant ACT_SETTLE_ALL = 0x0c;
    uint8 private constant ACT_TAKE = 0x0e;
    uint256 private constant _OPEN_DELTA = 0; // v4 ActionConstants.OPEN_DELTA sentinel (take all)  // docs: OPEN_DELTA = 0

    // ---- allowlists ----
    mapping(address => bool) public allowedRouters; // e.g., Universal Router, 0x router
    mapping(address => bool) public allowedSpenders; // e.g., 0x AllowanceTarget / Permit2

    // ---- modifiers ----
    modifier onlyExecutor() {
        if (msg.sender != executor) revert NOT_EXECUTOR();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _usdc,
        address _zora,
        address _universalRouter,
        address _executor,
        address _feeCollector,
        uint16 _feeBps,
        uint256 _minFeeAbsolute
    ) external initializer {
        if (
            _usdc == address(0) ||
            _zora == address(0) ||
            _universalRouter == address(0) ||
            _executor == address(0) ||
            _feeCollector == address(0)
        ) revert ZERO_ADDR();
        if (_feeBps > 500) revert FEE_TOO_HIGH(); // hard cap 5%

        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __Ownable2Step_init();

        _transferOwnership(msg.sender);

        USDC = IERC20(_usdc);
        ZORA = IERC20(_zora);
        executor = _executor;
        feeCollector = _feeCollector;
        feeBps = _feeBps;
        minFeeAbsolute = _minFeeAbsolute;

        PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

        // One-time infinite approval from THIS contract to Permit2
        USDC.safeApprove(address(PERMIT2), type(uint256).max);
        ZORA.safeApprove(address(PERMIT2), type(uint256).max);

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

    // Set absolute per-trade fee floor in USDC units (e.g., 20_000 = $0.02 for 6d tokens)
    function setMinFeeAbsolute(uint256 minAbs) external onlyOwner {
        minFeeAbsolute = minAbs;
        emit MinFeeAbsoluteChanged(minAbs);
    }

    function setRouterAllowed(address r, bool allowed) external onlyOwner {
        allowedRouters[r] = allowed;
        emit RouterAllowed(r, allowed);
    }

    // Sticky approval pattern for 0x spenders (gas-saver)
    function setSpenderAllowed(address s, bool allowed) external onlyOwner {
        allowedSpenders[s] = allowed;
        emit SpenderAllowed(s, allowed);
        if (allowed) {
            USDC.safeApprove(s, 0);
            USDC.safeApprove(s, type(uint256).max);
        } else {
            USDC.safeApprove(s, 0);
        }
    }

    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    function rescueETH(address payable to, uint256 amount) external onlyOwner {
        (bool ok, ) = to.call{ value: amount }("");
        if (!ok) revert ETH_TRANSFER_FAIL();
    }

    // External helper to compute fee and net amount for a given input
    function computeFeeAndNet(uint256 amountIn) external view returns (uint256 fee, uint256 net) {
        return _computeFeeAndNet(amountIn);
    }

    // ---- internal: shared fee calc ----
    function _computeFeeAndNet(uint256 amountIn) internal view returns (uint256 fee, uint256 net) {
        uint256 pctFee = (amountIn * feeBps) / _MAX_BPS;
        uint256 absFloor = minFeeAbsolute;
        fee = pctFee >= absFloor ? pctFee : absFloor;
        if (fee >= amountIn) revert AMOUNT_LT_MIN_FEE();
        net = amountIn - fee;
    }

    // ---------------------------
    // Universal Router (v4 single-pool) lane
    // ---------------------------
    function executeBatchUniV4Single(
        address universalRouter,
        V4SingleSwap[] calldata swaps
    ) external override nonReentrant onlyExecutor {
        if (universalRouter == address(0) || !allowedRouters[universalRouter]) revert ROUTER_NOT_ALLOWED();

        // cache hot storage
        IERC20 usdc = USDC;
        IPermit2 permit2 = PERMIT2;
        address feeTo = feeCollector;

        uint256 len = swaps.length;
        if (len == 0 || len > 500) revert BAD_BATCH_SIZE();

        // Pre-encode constant UR command/actions
        bytes memory commands = abi.encodePacked(uint8(CMD_V4_SWAP));
        bytes memory actions = abi.encodePacked(
            uint8(ACT_SWAP_EXACT_IN_SINGLE),
            uint8(ACT_SETTLE_ALL),
            uint8(ACT_TAKE) // TAKE(..., recipient, OPEN_DELTA)
        );

        uint256 totalNet;
        uint256 maxDeadline;

        // Pass 1: validate & aggregate (compute nets from declared amounts for Permit2 allowance)
        for (uint256 i; i < len; ) {
            V4SingleSwap calldata s = swaps[i];
            if (s.user == address(0) || s.recipient == address(0)) revert INVALID_ADDRESS();
            if (s.amountIn == 0 || s.minAmountOut == 0) revert INVALID_AMOUNTS();
            if (s.deadline < block.timestamp) revert EXPIRED_DEADLINE();

            address c0 = Currency.unwrap(s.key.currency0);
            address c1 = Currency.unwrap(s.key.currency1);
            bool c0IsUSDC = (c0 == address(usdc));
            bool c1IsUSDC = (c1 == address(usdc));
            if (!(c0IsUSDC || c1IsUSDC)) revert PATH_IN_MISMATCH();
            if (c0IsUSDC && !s.zeroForOne) revert PATH_IN_MISMATCH();
            if (c1IsUSDC && s.zeroForOne) revert PATH_IN_MISMATCH();

            (, uint256 netEst) = _computeFeeAndNet(uint256(s.amountIn));

            totalNet += netEst;
            if (s.deadline > maxDeadline) maxDeadline = s.deadline;

            unchecked {
                ++i;
            }
        }

        // Batch-scoped Permit2 approval for UR to pull NET USDC from THIS contract
        if (totalNet > type(uint160).max) revert INVALID_AMOUNTS();
        uint48 expiry = maxDeadline > type(uint48).max ? type(uint48).max : uint48(maxDeadline);
        permit2.approve(address(usdc), universalRouter, uint160(totalNet), expiry);

        uint256 totalFeeCollected;

        // Pass 2: pull USDC, compute fee from declared amountIn, then swap via UR
        for (uint256 i; i < len; ) {
            V4SingleSwap calldata s = swaps[i];

            usdc.safeTransferFrom(s.user, address(this), s.amountIn);
            (uint256 fee, uint256 net) = _computeFeeAndNet(uint256(s.amountIn));
            totalFeeCollected += fee;

            if (net > type(uint128).max) revert INVALID_AMOUNTS();

            Currency inCur = s.zeroForOne ? s.key.currency0 : s.key.currency1; // USDC side
            Currency outCur = s.zeroForOne ? s.key.currency1 : s.key.currency0;

            address tokenOutAddr = Currency.unwrap(outCur);
            if (tokenOutAddr == address(0)) revert INVALID_TOKEN_OUT();

            bytes[] memory params = new bytes[](3);

            // [0] SWAP_EXACT_IN_SINGLE
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
            // [2] TAKE(currencyOut, recipient, OPEN_DELTA=0)
            params[2] = abi.encode(outCur, s.recipient, uint256(0));

            bytes[] memory inputs = new bytes[](1);
            inputs[0] = abi.encode(actions, params);

            // (Optional defense) Track delivered out to recipient
            uint256 beforeBal = IERC20(tokenOutAddr).balanceOf(s.recipient);
            IUniversalRouter(universalRouter).execute(commands, inputs, s.deadline);
            uint256 afterBal = IERC20(tokenOutAddr).balanceOf(s.recipient);
            uint256 outAmt = afterBal > beforeBal ? (afterBal - beforeBal) : 0;

            // emit with tokenIn first, then tokenOut
            emit SwapExecuted(
                s.user,
                s.recipient,
                s.creator,
                address(usdc),
                tokenOutAddr,
                s.amountIn,
                fee,
                outAmt,
                universalRouter
            );

            unchecked {
                ++i;
            }
        }

        // Transfer aggregated fees once at the end
        if (totalFeeCollected != 0) usdc.safeTransfer(feeTo, totalFeeCollected);

        // Revoke UR's batch Permit2 allowance (defense-in-depth)
        permit2.approve(address(usdc), universalRouter, 0, 0);
    }

    // ---------------------------
    // 0x Swap API (router adapter) lane
    // ---------------------------
    function executeBatch0x(
        address expectedRouter,
        OxSwap[] calldata swaps
    ) external override nonReentrant onlyExecutor {
        if (expectedRouter == address(0) || !allowedRouters[expectedRouter]) revert ROUTER_NOT_ALLOWED();

        // cache hot storage
        IERC20 usdc = USDC;
        address feeTo = feeCollector;

        uint256 len = swaps.length;
        if (len == 0 || len > 500) revert BAD_BATCH_SIZE();

        uint256 totalFeeCollected;

        // Single pass: validate, pull, swap, enforce exact-input, accumulate fee, forward outs
        for (uint256 i; i < len; ) {
            OxSwap calldata s = swaps[i];

            if (s.user == address(0) || s.recipient == address(0)) revert INVALID_ADDRESS();
            if (s.tokenOut == address(0)) revert INVALID_TOKEN_OUT();
            if (s.amountIn == 0 || s.minAmountOut == 0) revert INVALID_AMOUNTS();
            if (s.deadline < block.timestamp) revert EXPIRED_DEADLINE();
            if (s.callTarget != expectedRouter) revert ROUTER_NOT_ALLOWED();
            if (!allowedSpenders[s.spender]) revert SPENDER_NOT_ALLOWED();
            if (s.value != 0) revert INVALID_AMOUNTS();

            // Pull USDC and compute fee from declared amountIn
            usdc.safeTransferFrom(s.user, address(this), s.amountIn);
            (uint256 fee, uint256 net) = _computeFeeAndNet(uint256(s.amountIn));
            totalFeeCollected += fee;

            // Record balances for exact-input enforcement and FoT-safe out measurement
            uint256 usdcBeforeSpend = usdc.balanceOf(address(this));
            IERC20 out = IERC20(s.tokenOut);
            uint256 beforeRecipient = out.balanceOf(s.recipient);
            uint256 beforeSelfOut = out.balanceOf(address(this));

            // Execute 0x call (spender already has sticky allowance)
            (bool ok, bytes memory ret) = s.callTarget.call{ value: s.value }(s.callData);
            if (!ok) {
                assembly {
                    revert(add(ret, 32), mload(ret))
                }
            }

            // Enforce exact-input (or refund if price improved)
            uint256 usdcAfterSpend = usdc.balanceOf(address(this));
            if (usdcAfterSpend > usdcBeforeSpend) revert INVALID_AMOUNTS();
            uint256 spent = usdcBeforeSpend - usdcAfterSpend;
            if (spent > net) revert INVALID_AMOUNTS();
            if (spent < net) usdc.safeTransfer(s.user, net - spent);

            // If router paid to us, forward only what arrived in THIS call
            uint256 afterSelfOut = out.balanceOf(address(this));
            uint256 deltaSelfOut = afterSelfOut > beforeSelfOut ? (afterSelfOut - beforeSelfOut) : 0;
            if (deltaSelfOut > 0) {
                out.safeTransfer(s.recipient, deltaSelfOut);
            }

            // Final slippage check AFTER forwarding
            uint256 afterRecipient = out.balanceOf(s.recipient);
            uint256 outAmt = afterRecipient > beforeRecipient ? (afterRecipient - beforeRecipient) : 0;
            if (outAmt < s.minAmountOut) revert SLIPPAGE();

            // emit with tokenIn first, then tokenOut
            emit SwapExecuted(
                s.user,
                s.recipient,
                s.creator,
                address(usdc),
                s.tokenOut,
                s.amountIn,
                fee,
                outAmt,
                s.callTarget
            );

            unchecked {
                ++i;
            }
        }

        // Transfer aggregated fees once at the end
        if (totalFeeCollected != 0) usdc.safeTransfer(feeTo, totalFeeCollected);
    }

    // Pack the three v4 actions once.
    function _v4Actions() internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(ACT_SWAP_EXACT_IN_SINGLE), uint8(ACT_SETTLE_ALL), uint8(ACT_TAKE));
    }

    // Encode a single v4 exact-in swap: SETTLE_ALL(ZORA, amount) -> TAKE(out, recipient, OPEN_DELTA)
    function _encodeV4Single(
        bytes memory actions,
        PoolKey calldata key,
        bool zIsC0,
        uint128 zoraIn,
        uint128 minOut,
        Currency inCur, // ZORA
        Currency outCur, // creator token
        address recipient
    ) internal pure returns (bytes memory) {
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zIsC0,
                amountIn: zoraIn,
                amountOutMinimum: minOut,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(inCur, uint256(zoraIn)); // SETTLE_ALL cap
        params[2] = abi.encode(outCur, recipient, uint256(_OPEN_DELTA)); // TAKE all owed
        return abi.encode(actions, params);
    }

    // Small helper to write a batch-scoped Permit2 approval (with uint160 guard)
    function _approveBatch(IPermit2 permit2, address token, address spender, uint256 amount, uint48 expiry) internal {
        if (amount > type(uint160).max) revert INVALID_AMOUNTS();
        permit2.approve(token, spender, uint160(amount), expiry);
    }

    function executeZoraCreatorCoinOneToMany(
        address universalRouter,
        ZoraCreatorCoinOneToMany calldata s
    ) external override nonReentrant onlyExecutor {
        if (universalRouter == address(0) || !allowedRouters[universalRouter]) revert ROUTER_NOT_ALLOWED();
        if (s.deadline < block.timestamp) revert EXPIRED_DEADLINE();

        IERC20 usdc = USDC;
        IERC20 zora = ZORA;
        if (address(zora) == address(0)) revert ZERO_ADDR();

        uint256 len = s.payees.length;
        if (len == 0 || len > 500) revert BAD_BATCH_SIZE(); // keep within block gas

        // --- Derive pool sides & tokenOut (creator coin) ---
        address zAddr = address(zora);
        address c0 = Currency.unwrap(s.key.currency0);
        address c1 = Currency.unwrap(s.key.currency1);
        bool zIsC0 = (c0 == zAddr);
        bool zIsC1 = (c1 == zAddr);
        if (!(zIsC0 || zIsC1)) revert PATH_IN_MISMATCH();

        address tokenOutAddr = zIsC0 ? c1 : c0;
        if (tokenOutAddr == address(0)) revert INVALID_TOKEN_OUT();
        if (tokenOutAddr == address(usdc) || tokenOutAddr == address(zora)) revert INVALID_TOKEN_OUT();
        IERC20 tokenOut = IERC20(tokenOutAddr);

        // --- Pull USDC per user; record gross; aggregate totals ---
        uint256 totalGross;
        uint256[] memory gross = new uint256[](len);
        for (uint256 i; i < len; ) {
            Payee calldata p = s.payees[i];
            if (p.user == address(0) || p.recipient == address(0)) revert INVALID_ADDRESS();
            if (p.amountIn == 0) revert INVALID_AMOUNTS();

            uint256 g = uint256(p.amountIn);
            usdc.safeTransferFrom(p.user, address(this), g);

            gross[i] = g;
            totalGross += g;

            unchecked {
                ++i;
            }
        }

        // --- Apply fee ONCE per batch; pro-rate across payees by gross ---
        // Use shared helper for consistency with other lanes
        (uint256 totalFee, uint256 totalNet) = _computeFeeAndNet(totalGross);

        // --- Approve UR to pull NET USDC via Permit2 (scoped) ---
        uint48 expiry = s.deadline > type(uint48).max ? type(uint48).max : uint48(s.deadline);
        _approveBatch(PERMIT2, address(usdc), universalRouter, totalNet, expiry);

        // ---- Leg 1: V3 USDC -> ZORA (exact-in) ----
        bytes memory cmdV3 = abi.encodePacked(uint8(CMD_V3_SWAP_EXACT_IN));
        bytes[] memory inV3 = new bytes[](1);
        bytes memory path = abi.encodePacked(address(usdc), s.v3Fee, address(zora));
        inV3[0] = abi.encode(address(this), totalNet, s.minZoraOut, path, true);

        uint256 zoraBefore = zora.balanceOf(address(this));
        IUniversalRouter(universalRouter).execute(cmdV3, inV3, s.deadline);
        uint256 zoraIn = zora.balanceOf(address(this)) - zoraBefore;

        // --- Approve UR to pull the ZORA actually received ---
        _approveBatch(PERMIT2, address(zora), universalRouter, zoraIn, expiry);
        if (zoraIn > type(uint128).max) revert INVALID_AMOUNTS(); // v4 param width

        // ---- Leg 2: V4 ZORA -> creator coin (exact-in), TAKE to this contract ----
        bytes memory cmdV4 = abi.encodePacked(uint8(CMD_V4_SWAP));
        bytes[] memory inV4 = new bytes[](1);

        bytes memory actions = _v4Actions();
        Currency inCur = zIsC0 ? s.key.currency0 : s.key.currency1; // ZORA
        Currency outCur = zIsC0 ? s.key.currency1 : s.key.currency0; // creator coin

        inV4[0] = _encodeV4Single(
            actions,
            s.key,
            zIsC0,
            uint128(zoraIn),
            s.minCreatorOut,
            inCur,
            outCur,
            address(this) // receive creator coin here, then fan out
        );

        uint256 outBefore = tokenOut.balanceOf(address(this));
        IUniversalRouter(universalRouter).execute(cmdV4, inV4, s.deadline);
        uint256 outAmt = tokenOut.balanceOf(address(this)) - outBefore;

        // ---- Pro-rata distribution by NET USDC (weights = nets[i]) ----
        uint256 distributed;
        for (uint256 i; i < len; ) {
            address recipient = s.payees[i].recipient;
            address user = s.payees[i].user;
            uint256 net = Math.mulDiv(totalNet, gross[i], totalGross); // floor
            uint256 payout = Math.mulDiv(outAmt, net, totalNet); // floor; full-precision
            if (payout != 0) tokenOut.safeTransfer(recipient, payout);
            distributed += payout;

            emit ReactionSwapExecuted(
                user,
                recipient,
                s.creator,
                s.payees[i].amountIn,
                payout,
                s.payees[i].creatorAttributions
            );

            unchecked {
                ++i;
            }
        }

        // Handle rounding dust (tokenOut)
        uint256 rem = tokenOut.balanceOf(address(this));
        if (rem != 0) tokenOut.safeTransfer(feeCollector, rem);

        // ---- Aggregate fee transfer & revoke scoped allowances ----
        if (totalFee != 0) usdc.safeTransfer(feeCollector, totalFee);

        PERMIT2.approve(address(usdc), universalRouter, 0, 0);
        PERMIT2.approve(address(zora), universalRouter, 0, 0);

        emit BatchReactionSwap(address(usdc), tokenOutAddr, totalGross, outAmt, totalFee, universalRouter);
    }

    // ---- UUPS ----
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
