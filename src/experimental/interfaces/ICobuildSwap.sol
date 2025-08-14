// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

interface ICobuildSwap {
    // ---- events ----
    event SwapExecuted(
        address indexed user,
        address indexed recipient,
        address creator,
        address tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 fee,
        uint256 amountOut,
        address router
    );
    event ExecutorChanged(address indexed oldExec, address indexed newExec);
    event FeeParamsChanged(uint16 feeBps, address feeCollector);
    event RouterAllowed(address router, bool allowed);
    event MinFeeAbsoluteChanged(uint256 minFeeAbsolute);
    event SpenderAllowed(address spender, bool allowed);

    // ---- errors ----
    error FEE_TOO_HIGH();
    error ZERO_ADDR();
    error NOT_EXECUTOR();
    error PATH_IN_MISMATCH();
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
    error AMOUNT_LT_MIN_FEE();

    // ---- 0x swap ----
    struct OxOneToMany {
        address creator; // attribution only (analytics)
        address tokenOut; // token that 0x will deliver to THIS contract
        uint256 minAmountOut; // total slippage floor (sum over payees)
        address spender; // 0x AllowanceTarget/Permit2 spender from quote
        address callTarget; // 0x router "to" address from quote
        bytes callData; // 0x calldata (set taker & recipient = this contract)
        uint256 value; // native value (usually 0)
        uint256 deadline; // safety deadline for this swap
        Payee[] payees; // at least 1
    }

    // --- REPLACES the old executeBatch0x signature ---
    function executeBatch0x(address expectedRouter, OxOneToMany calldata s) external;

    // --- compact inputs ---
    struct Payee {
        address user; // token payer we pull from
        address recipient; // receives creator coin
        uint256 amountIn; // gross token (6d)
    }

    struct ZoraCreatorCoinOneToMany {
        address creator; // attribution only (analytics)
        PoolKey key; // v4 pool: ZORA <-> creator coin
        uint24 v3Fee; // USDC<->ZORA fee tier
        uint256 deadline; // applies to both legs
        uint256 minZoraOut; // USDC->ZORA leg floor (sum)
        uint128 minCreatorOut; // ZORA->creator leg floor (sum)
        Payee[] payees; // at least 1
    }

    event BatchReactionSwap(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee,
        address router
    );

    // --- NEW: one-swap-many-payouts entrypoint ---
    function executeZoraCreatorCoinOneToMany(address universalRouter, ZoraCreatorCoinOneToMany calldata s) external;
}
