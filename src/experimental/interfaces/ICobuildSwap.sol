// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

interface ICobuildSwap {
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
    error NO_ETH_TERMINAL();
    error JB_TOKEN_UNAVAILABLE();

    // ---- 0x swap ----
    struct OxOneToMany {
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

    // ---- Universal Router USDC -> ETH -> JB pay -> fan-out ----
    struct JuiceboxPayMany {
        // Router and swap controls (built on-chain as USDC -> WETH(v3) -> UNWRAP -> ETH to this)
        address universalRouter; // must be allow-listed
        uint24 v3Fee; // USDC/WETH fee tier (e.g., 500, 3000, 10000)
        uint256 deadline; // UR deadline
        // Juicebox pay
        uint256 projectId; // JB project to pay
        uint256 minEthOut; // floor for ETH we must receive from UR
        string memo;
        bytes metadata; // include preferClaimedTokens=true for your JB version
        // recipients
        Payee[] payees; // pro-rata by gross USDC
    }

    // --- NEW: one-swap-many-payouts entrypoint ---
    function executeZoraCreatorCoinOneToMany(address universalRouter, ZoraCreatorCoinOneToMany calldata s) external;

    // NEW: expose the UR-only entrypoint
    function executeJuiceboxPayMany(JuiceboxPayMany calldata s) external;
}
