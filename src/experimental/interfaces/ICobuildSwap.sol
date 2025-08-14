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

    // ---- v4 single-pool swap ----
    struct V4SingleSwap {
        address user; // USDC owner we pull from
        address recipient; // who receives tokenOut
        address creator; // whoever's content triggered this swap
        PoolKey key; // v4 pool id
        bool zeroForOne; // true if currency0 -> currency1
        uint128 amountIn; // USDC (6d)
        uint128 minAmountOut; // slippage bound
        uint256 deadline; // UR.execute deadline for THIS swap
    }

    function executeBatchUniV4Single(address universalRouter, V4SingleSwap[] calldata swaps) external;

    // ---- 0x swap ----
    struct OxSwap {
        address user; // pulls USDC from here
        address recipient; // final holder of tokenOut
        address creator; // whoever's content triggered this swap
        address tokenOut; // expected output token (for checks/transfer)
        uint256 amountIn; // gross USDC
        uint256 minAmountOut; // slippage bound
        address spender; // 0x AllowanceTarget/Permit2 spender from quote
        address callTarget; // 0x router "to" from quote
        bytes callData; // 0x calldata
        uint256 value; // native value (usually 0)
        uint256 deadline; // safety deadline
    }

    function executeBatch0x(address expectedRouter, OxSwap[] calldata swaps) external;

    // --- compact inputs ---
    struct Payee {
        address user; // token payer we pull from
        address recipient; // receives creator coin
        uint256 amountIn; // gross token (6d)
        CreatorAttribution[] creatorAttributions; // at least 1
    }

    struct CreatorAttribution {
        address creator;
        uint256 amount;
        bytes data;
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

    event ReactionSwapExecuted(
        address indexed user,
        address indexed recipient,
        address creator,
        uint256 amountIn,
        uint256 amountOut,
        CreatorAttribution[] creatorAttributions
    );

    // --- NEW: one-swap-many-payouts entrypoint ---
    function executeZoraCreatorCoinOneToMany(address universalRouter, ZoraCreatorCoinOneToMany calldata s) external;
}
