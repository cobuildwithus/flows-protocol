// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

interface ICobuildSwap {
    // ---- events ----
    event SwapExecuted(
        address indexed user,
        address indexed recipient,
        address indexed tokenOut, // NOTE: not indexed (Solidity max 3 indexed params per event)
        address tokenIn, // base token used to pay in + where fee is taken
        uint256 amountIn,
        uint256 fee,
        uint256 amountOut,
        address router
    );
    event ExecutorChanged(address indexed oldExec, address indexed newExec);
    event FeeParamsChanged(uint16 feeBps, address feeCollector);
    event RouterAllowed(address router, bool allowed);

    // ---- errors ----
    error FEE_TOO_HIGH();
    error ZERO_ADDR();
    error NOT_EXECUTOR();
    error BAD_PATH_LEN(); // reserved (v3-style)
    error PATH_IN_MISMATCH();
    error PATH_OUT_MISMATCH(); // reserved (v3-style)
    error ROUTER_NOT_ALLOWED();
    error SPENDER_NOT_ALLOWED();
    error BAD_BATCH_SIZE();
    error INVALID_ADDRESS();
    error INVALID_TOKEN_OUT();
    error INVALID_AMOUNTS();
    error EXPIRED_DEADLINE();
    error NET_AMOUNT_ZERO();
    error SLIPPAGE();
    error ETH_TRANSFER_FAIL();
    error USDC_BALANCE_INCREASED();

    // ---- v4 single-pool swap ----
    struct V4SingleSwap {
        address user; // USDC owner we pull from
        address recipient; // who receives tokenOut
        PoolKey key; // v4 pool id
        bool zeroForOne; // true if currency0 -> currency1
        uint128 amountIn; // USDC (6d)
        uint128 minAmountOut; // slippage bound
        uint256 deadline; // UR.execute deadline for THIS swap
    }

    function executeBatchUniV4Single(
        address universalRouter,
        V4SingleSwap[] calldata swaps
    ) external returns (uint256[] memory amountsOut);

    // ---- 0x swap ----
    struct OxSwap {
        address user; // pulls USDC from here
        address recipient; // final holder of tokenOut
        address tokenOut; // expected output token (for checks/transfer)
        uint256 amountIn; // gross USDC
        uint256 minAmountOut; // slippage bound
        address spender; // 0x v2 AllowanceHolder/Permit2 spender from quote
        address callTarget; // 0x router "to" from quote
        bytes callData; // 0x calldata
        uint256 value; // native value (usually 0)
        uint256 deadline; // safety deadline
    }

    function executeBatch0x(
        address expectedRouter,
        OxSwap[] calldata swaps
    ) external returns (uint256[] memory amountsOut);
}
