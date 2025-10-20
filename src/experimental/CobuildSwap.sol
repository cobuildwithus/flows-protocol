// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IJBTerminal } from "../interfaces/external/juicebox/IJBTerminal.sol";
import { IJBDirectory } from "../interfaces/external/juicebox/IJBDirectory.sol";
import { JBConstants } from "../interfaces/external/juicebox/library/JBConstants.sol";
import { IJBTokens } from "../interfaces/external/juicebox/IJBTokens.sol";
import { IJBToken } from "../interfaces/external/juicebox/IJBToken.sol";

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
    IJBDirectory public JB_DIRECTORY;
    IJBTokens public JB_TOKENS;
    address public WETH9; // WETH9 address for UR v3 path building

    address public executor;
    address public feeCollector;
    uint16 public feeBps; // e.g., 200 = 2%

    // Absolute per-trade fee floor, denominated in USDC/base token units
    uint256 public minFeeAbsolute;

    // ---- constants ----
    uint256 private constant _MAX_BPS = 10_000;
    uint256 private constant _MAX_PAYEES = 500;

    // Universal Router: command & v4 action constants
    uint8 private constant CMD_V4_SWAP = 0x10;
    uint8 private constant CMD_V3_SWAP_EXACT_IN = 0x00; // <— NEW (v3 hop)
    uint8 private constant CMD_UNWRAP_WETH = 0x0c; // Universal Router Payments.unwrapWETH9(recipient, amountMin)
    uint8 private constant ACT_SWAP_EXACT_IN_SINGLE = 0x06;
    uint8 private constant ACT_SETTLE = 0x0b;
    uint8 private constant ACT_TAKE = 0x0e;
    uint256 private constant _OPEN_DELTA = 0; // v4 ActionConstants.OPEN_DELTA sentinel (take all)  // docs: OPEN_DELTA = 0
    uint256 private constant _CONTRACT_BALANCE = 1 << 255; // v4 ActionConstants.CONTRACT_BALANCE

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
        address _jbDirectory,
        address _jbTokens,
        address _weth9,
        address _executor,
        address _feeCollector,
        uint16 _feeBps,
        uint256 _minFeeAbsolute
    ) external initializer {
        if (
            _usdc == address(0) ||
            _zora == address(0) ||
            _universalRouter == address(0) ||
            _jbDirectory == address(0) ||
            _jbTokens == address(0) ||
            _weth9 == address(0) ||
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
        JB_DIRECTORY = IJBDirectory(_jbDirectory);
        JB_TOKENS = IJBTokens(_jbTokens);
        WETH9 = _weth9;
        executor = _executor;
        feeCollector = _feeCollector;
        feeBps = _feeBps;
        minFeeAbsolute = _minFeeAbsolute;

        PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

        // One-time infinite approval from THIS contract to Permit2
        USDC.approve(address(PERMIT2), type(uint256).max);
        ZORA.approve(address(PERMIT2), type(uint256).max);

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

    // Manage 0x spender allowlist; allowances are now granted per-call in executeBatch0x
    function setSpenderAllowed(address s, bool allowed) external onlyOwner {
        allowedSpenders[s] = allowed;
        emit SpenderAllowed(s, allowed);
        if (!allowed) {
            // Revoke any lingering allowance on disallow
            USDC.approve(s, 0);
        }
    }

    function setJuiceboxAddresses(address directory, address tokens) external onlyOwner {
        if (directory == address(0) || tokens == address(0)) revert ZERO_ADDR();
        JB_DIRECTORY = IJBDirectory(directory);
        JB_TOKENS = IJBTokens(tokens);
        emit JuiceboxAddressesUpdated(directory, tokens);
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
    // 0x Swap API (router adapter) lane
    // ---------------------------
    function executeBatch0x(
        address expectedRouter,
        OxOneToMany calldata s
    ) external override nonReentrant onlyExecutor {
        if (expectedRouter == address(0) || !allowedRouters[expectedRouter]) revert ROUTER_NOT_ALLOWED();
        if (s.deadline < block.timestamp) revert EXPIRED_DEADLINE();
        if (s.tokenOut == address(0)) revert INVALID_TOKEN_OUT();
        if (s.value != 0) revert INVALID_AMOUNTS();
        if (s.callTarget != expectedRouter) revert ROUTER_NOT_ALLOWED();
        if (!allowedSpenders[s.spender]) revert SPENDER_NOT_ALLOWED();
        // AllowanceHolder flow invariant: spender == entry point
        if (s.spender != s.callTarget) revert SPENDER_NOT_ALLOWED();

        IERC20 usdc = USDC;
        IERC20 out = IERC20(s.tokenOut);
        if (s.tokenOut == address(usdc)) revert INVALID_TOKEN_OUT();

        uint256 len = s.payees.length;
        if (len == 0 || len > _MAX_PAYEES) revert BAD_BATCH_SIZE();

        // --- Pull USDC from all payees; sum gross ---
        uint256 totalGross;
        for (uint256 i; i < len; ) {
            Payee calldata p = s.payees[i];
            if (p.user == address(0) || p.recipient == address(0)) revert INVALID_ADDRESS();
            if (p.amountIn == 0) revert INVALID_AMOUNTS();

            usdc.transferFrom(p.user, address(this), p.amountIn);
            totalGross += p.amountIn;

            unchecked {
                ++i;
            }
        }

        // --- Apply fee once on the total gross ---
        (uint256 totalFee, uint256 totalNet) = _computeFeeAndNet(totalGross);
        if (totalNet == 0) revert NET_AMOUNT_ZERO();

        // --- Execute the 0x swap (output MUST arrive at this contract) ---
        uint256 usdcBeforeSpend = usdc.balanceOf(address(this));
        uint256 beforeOut = out.balanceOf(address(this));

        // Per-call bounded allowance for the active spender
        usdc.safeApprove(s.spender, 0);
        usdc.safeApprove(s.spender, totalNet);

        // Execute the 0x swap
        (bool ok, bytes memory ret) = s.callTarget.call{ value: s.value }(s.callData);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }

        // Cleanup: always leave zero allowance
        usdc.safeApprove(s.spender, 0);
        if (usdc.allowance(address(this), s.spender) != 0) revert INVALID_AMOUNTS();

        // Enforce exact-input (0x must not spend more than totalNet).
        uint256 usdcAfterSpend = usdc.balanceOf(address(this));
        if (usdcAfterSpend > usdcBeforeSpend) revert INVALID_AMOUNTS();
        uint256 spent = usdcBeforeSpend - usdcAfterSpend;
        if (spent > totalNet) revert INVALID_AMOUNTS();

        if (spent < totalNet) {
            // refund USDC to the fee collector
            usdc.transfer(feeCollector, totalNet - spent);
        }

        // Measure output that arrived here; require it meets the aggregated slippage floor
        uint256 afterOut = out.balanceOf(address(this));
        uint256 outAmt = afterOut > beforeOut ? (afterOut - beforeOut) : 0;
        if (outAmt < s.minAmountOut) revert SLIPPAGE();

        emit BatchReactionSwap(address(usdc), s.tokenOut, totalGross, outAmt, totalFee, s.callTarget);

        // --- Distribute tokenOut pro‑rata by gross amountIn (matches fee calc basis) ---
        uint256 distributed;
        for (uint256 i; i < len; ) {
            Payee calldata p = s.payees[i];
            uint256 payout = Math.mulDiv(outAmt, p.amountIn, totalGross);
            if (payout != 0) {
                out.safeTransfer(p.recipient, payout);
                distributed += payout;
            }
            unchecked {
                ++i;
            }
        }
        // Send remainder to fee collector to eliminate rounding dust
        uint256 remainderOut = outAmt - distributed;
        if (remainderOut != 0) out.safeTransfer(feeCollector, remainderOut);

        // --- Sweep: transfer USDC fee; send any leftover tokenOut dust to feeCollector ---
        if (totalFee != 0) usdc.transfer(feeCollector, totalFee);
        uint256 dustOut = out.balanceOf(address(this));
        if (dustOut != 0) out.safeTransfer(feeCollector, dustOut);
    }
    // Encode v4: SETTLE(ZORA, CONTRACT_BALANCE, router-pays) -> SWAP_EXACT_IN_SINGLE(OPEN_DELTA) -> TAKE(OPEN_DELTA)
    function _encodeSettleSwapTakeV4(
        PoolKey calldata key,
        bool zIsC0,
        uint128 minOut,
        Currency inCur, // ZORA
        Currency outCur, // creator token
        address recipient
    ) internal pure returns (bytes memory) {
        bytes memory actions = abi.encodePacked(uint8(ACT_SETTLE), uint8(ACT_SWAP_EXACT_IN_SINGLE), uint8(ACT_TAKE));
        bytes[] memory params = new bytes[](3);
        // [0] SETTLE from router balance
        params[0] = abi.encode(inCur, _CONTRACT_BALANCE, false);
        // [1] SWAP with OPEN_DELTA input
        params[1] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zIsC0,
                amountIn: uint128(_OPEN_DELTA),
                amountOutMinimum: minOut,
                hookData: bytes("")
            })
        );
        // [2] TAKE all owed to recipient
        params[2] = abi.encode(outCur, recipient, uint256(_OPEN_DELTA));
        return abi.encode(actions, params);
    }

    // Build the concatenated Universal Router commands and inputs for V3 exact-in then V4 settle/swap/take
    function _buildV3V4CommandsAndInputs(
        address universalRouter,
        address usdc,
        address zora,
        uint256 totalNet,
        uint256 minZoraOut,
        uint24 v3Fee,
        PoolKey calldata key,
        bool zIsC0,
        uint128 minCreatorOut,
        address recipient
    ) internal pure returns (bytes memory commands, bytes[] memory inputs) {
        commands = abi.encodePacked(uint8(CMD_V3_SWAP_EXACT_IN), uint8(CMD_V4_SWAP));

        inputs = new bytes[](2);

        // Input[0]: V3 USDC -> ZORA (recipient = Universal Router)
        bytes memory path = abi.encodePacked(usdc, v3Fee, zora);
        inputs[0] = abi.encode(universalRouter, totalNet, minZoraOut, path, true);

        // Input[1]: V4 SETTLE(ZORA, CONTRACT_BALANCE, router-pays) -> SWAP(OPEN_DELTA) -> TAKE(OPEN_DELTA)
        Currency inCur = zIsC0 ? key.currency0 : key.currency1; // ZORA
        Currency outCur = zIsC0 ? key.currency1 : key.currency0; // creator coin
        inputs[1] = _encodeSettleSwapTakeV4(key, zIsC0, minCreatorOut, inCur, outCur, recipient);
    }

    // Build Universal Router commands/inputs for USDC -> WETH(v3) -> UNWRAP -> ETH to this contract
    function _buildUSDCtoETH_UR(
        address universalRouter,
        uint256 amountIn,
        uint256 minEthOut,
        uint24 v3Fee
    ) internal view returns (bytes memory commands, bytes[] memory inputs) {
        if (WETH9 == address(0)) revert ZERO_ADDR();
        // commands: V3_SWAP_EXACT_IN then UNWRAP_WETH
        commands = abi.encodePacked(bytes1(CMD_V3_SWAP_EXACT_IN), bytes1(CMD_UNWRAP_WETH));

        inputs = new bytes[](2);

        // v3 path USDC -> WETH9
        bytes memory path = abi.encodePacked(address(USDC), v3Fee, WETH9);

        // [0] V3_SWAP_EXACT_IN(recipient = UR, amountIn, amountOutMin, path, payerIsUser=true)
        inputs[0] = abi.encode(universalRouter, amountIn, minEthOut, path, true);

        // [1] UNWRAP_WETH(recipient = this, amountMin = minEthOut)
        inputs[1] = abi.encode(address(this), minEthOut);
    }

    function executeZoraCreatorCoinOneToMany(
        address universalRouter,
        ZoraCreatorCoinOneToMany calldata s
    ) external override nonReentrant onlyExecutor {
        if (universalRouter == address(0) || !allowedRouters[universalRouter]) revert ROUTER_NOT_ALLOWED();
        if (s.deadline < block.timestamp) revert EXPIRED_DEADLINE();

        IERC20 usdc = USDC;
        address zAddr = address(ZORA);

        // cache hot values
        address feeTo = feeCollector;
        address self = address(this);

        uint256 len = s.payees.length;
        if (len == 0 || len > _MAX_PAYEES) revert BAD_BATCH_SIZE();

        // --- Derive pool sides & tokenOut (creator coin) ---
        address c0 = Currency.unwrap(s.key.currency0);
        address c1 = Currency.unwrap(s.key.currency1);
        bool zIsC0 = (c0 == zAddr);
        if (!zIsC0 && c1 != zAddr) revert PATH_IN_MISMATCH();

        address tokenOutAddr = zIsC0 ? c1 : c0;
        if (tokenOutAddr == address(0) || tokenOutAddr == address(usdc) || tokenOutAddr == zAddr) {
            revert INVALID_TOKEN_OUT();
        }
        IERC20 tokenOut = IERC20(tokenOutAddr);

        // --- Pull USDC per user; aggregate gross ---
        uint256 totalGross;
        for (uint256 i = 0; i < len; ) {
            Payee calldata p = s.payees[i];
            if (p.user == address(0) || p.recipient == address(0)) revert INVALID_ADDRESS();
            if (p.amountIn == 0) revert INVALID_AMOUNTS();

            usdc.transferFrom(p.user, self, p.amountIn);

            unchecked {
                totalGross += p.amountIn;
                ++i;
            }
        }

        // --- Apply fee once per batch ---
        (uint256 totalFee, uint256 totalNet) = _computeFeeAndNet(totalGross);
        if (totalNet == 0) revert NET_AMOUNT_ZERO();

        // --- Build & execute UR call in a tight scope (drop temps before loop) ---
        uint256 outAmt;
        {
            (bytes memory commands, bytes[] memory inputs) = _buildV3V4CommandsAndInputs(
                universalRouter,
                address(usdc),
                zAddr,
                totalNet,
                s.minZoraOut,
                s.v3Fee,
                s.key,
                zIsC0,
                s.minCreatorOut,
                self
            );

            // Execute and measure FoT-safe out amount; assert exact USDC spend == totalNet
            // --- Before calling Universal Router ---
            if (totalNet > type(uint160).max) revert INVALID_AMOUNTS(); // Permit2 amount is uint160
            uint48 exp = uint48(block.timestamp + 10 minutes);
            PERMIT2.approve(address(usdc), universalRouter, uint160(totalNet), exp);

            uint256 usdcBefore = usdc.balanceOf(self);
            uint256 beforeOut = tokenOut.balanceOf(self);
            IUniversalRouter(universalRouter).execute(commands, inputs, s.deadline);
            // --- Always revoke after ---
            PERMIT2.approve(address(usdc), universalRouter, 0, 0);
            uint256 usdcAfter = usdc.balanceOf(self);
            if (usdcBefore < usdcAfter) revert INVALID_AMOUNTS();
            if (usdcBefore - usdcAfter != totalNet) revert INVALID_AMOUNTS();
            uint256 afterOut = tokenOut.balanceOf(self);
            outAmt = afterOut > beforeOut ? (afterOut - beforeOut) : 0;
            if (outAmt < s.minCreatorOut) revert SLIPPAGE();
        } // commands/inputs out of scope here

        emit BatchReactionSwap(address(usdc), tokenOutAddr, totalGross, outAmt, totalFee, universalRouter);

        // --- Pro‑rata distribution by gross (matches fee calc on total gross) ---
        for (uint256 i = 0; i < len; ) {
            Payee calldata p = s.payees[i];
            uint256 payout = Math.mulDiv(outAmt, p.amountIn, totalGross);

            if (payout != 0) tokenOut.safeTransfer(p.recipient, payout);

            unchecked {
                ++i;
            }
        }

        // --- Sweep rounding dust & transfer fee ---
        uint256 rem = tokenOut.balanceOf(self);
        if (rem != 0) tokenOut.safeTransfer(feeTo, rem);
        if (totalFee != 0) usdc.transfer(feeTo, totalFee);
    }

    /// @notice USDC (many) -> ETH via Universal Router -> single JB pay -> ERC20 fan-out to many recipients.
    /// @dev Assumes the UR route UNWRAPS to native ETH and sends it to THIS contract.
    ///      Reverts if project ERC-20 is unavailable (not issued or preferClaimed was false).
    function executeJuiceboxPayMany(JuiceboxPayMany calldata s) external override nonReentrant onlyExecutor {
        // --- Basic checks ---
        if (s.universalRouter == address(0) || !allowedRouters[s.universalRouter]) revert ROUTER_NOT_ALLOWED();
        if (s.deadline < block.timestamp) revert EXPIRED_DEADLINE();
        if (WETH9 == address(0) || address(JB_DIRECTORY) == address(0) || address(JB_TOKENS) == address(0)) {
            revert ZERO_ADDR();
        }
        uint256 n = s.payees.length;
        if (n == 0 || n > _MAX_PAYEES) revert BAD_BATCH_SIZE();
        if (s.v3Fee != 100 && s.v3Fee != 500 && s.v3Fee != 3000 && s.v3Fee != 10000) revert INVALID_V3_FEE();
        if (s.minEthOut == 0) revert INVALID_MIN_OUT();
        // Guard against zero address before calling projectIdOf
        if (s.projectToken == address(0)) revert INVALID_ADDRESS();

        // Derive projectId from projectToken via IJBTokens
        uint256 projectId = JB_TOKENS.projectIdOf(IJBToken(s.projectToken));
        if (projectId == 0) revert JB_TOKEN_UNAVAILABLE();

        // Early check: ensure project has a primary ETH terminal before swapping
        IJBTerminal terminal = JB_DIRECTORY.primaryTerminalOf(projectId, JBConstants.NATIVE_TOKEN);
        if (address(terminal) == address(0)) revert NO_ETH_TERMINAL();

        IERC20 usdc = USDC;

        // --- 1) Pull USDC & sum gross ---
        uint256 totalGross;
        for (uint256 i; i < n; ) {
            Payee calldata p = s.payees[i];
            if (p.user == address(0) || p.recipient == address(0)) revert INVALID_ADDRESS();
            if (p.amountIn == 0) revert INVALID_AMOUNTS();
            usdc.transferFrom(p.user, address(this), p.amountIn);
            totalGross += p.amountIn;
            unchecked {
                ++i;
            }
        }

        // --- 2) Fee once on gross ---
        (uint256 feeUSDC, uint256 totalNetUSDC) = _computeFeeAndNet(totalGross);
        if (totalNetUSDC == 0) revert NET_AMOUNT_ZERO();

        // --- 3) Build UR program on-chain: USDC -> WETH(v3) -> UNWRAP -> ETH to this ---
        (bytes memory commands, bytes[] memory inputs) = _buildUSDCtoETH_UR(
            s.universalRouter,
            totalNetUSDC,
            s.minEthOut,
            s.v3Fee
        );

        // Permit2 bounded approval and execute
        if (totalNetUSDC > type(uint160).max) revert INVALID_AMOUNTS();
        uint48 exp = uint48(block.timestamp + 10 minutes);

        uint256 usdcBefore = usdc.balanceOf(address(this));
        uint256 ethBefore = address(this).balance;

        PERMIT2.approve(address(usdc), s.universalRouter, uint160(totalNetUSDC), exp);
        IUniversalRouter(s.universalRouter).execute(commands, inputs, s.deadline);
        PERMIT2.approve(address(usdc), s.universalRouter, 0, 0);

        // Enforce exact spend for V3 exact-in swap
        uint256 usdcAfter = usdc.balanceOf(address(this));
        if (usdcAfter > usdcBefore) revert INVALID_AMOUNTS();
        uint256 spent = usdcBefore - usdcAfter;
        if (spent != totalNetUSDC) revert INVALID_AMOUNTS();

        uint256 ethAfter = address(this).balance;
        if (ethAfter < ethBefore) revert INVALID_AMOUNTS();
        uint256 ethOut = ethAfter - ethBefore;
        if (ethOut < s.minEthOut) revert SLIPPAGE();

        // --- 4) JB pay (beneficiary = this contract) ---

        // Capture token address and balance before pay to compute minted delta
        uint256 beforeBal = IERC20(s.projectToken).balanceOf(address(this));

        terminal.pay{ value: ethOut }(
            projectId,
            JBConstants.NATIVE_TOKEN,
            ethOut,
            address(this),
            0,
            s.memo,
            s.metadata
        );

        // --- 5) ERC-20 fan-out (requires ERC-20 issued + preferClaimed honored) ---

        IERC20 t = IERC20(s.projectToken);
        uint256 afterBal = t.balanceOf(address(this));
        uint256 minted;
        if (afterBal < beforeBal) revert INVALID_AMOUNTS();
        minted = afterBal - beforeBal;

        if (minted == 0) revert ZERO_MINT_TO_BENEFICIARY();

        emit BatchReactionSwap(address(usdc), s.projectToken, totalGross, minted, feeUSDC, s.universalRouter);

        uint256 distributed;
        for (uint256 i; i < n; ) {
            Payee calldata p = s.payees[i];
            uint256 outAmount = Math.mulDiv(minted, p.amountIn, totalGross);
            if (outAmount != 0) {
                t.safeTransfer(p.recipient, outAmount);
                distributed += outAmount;
            }
            unchecked {
                ++i;
            }
        }
        // Sweep rounding remainder from minted amount only & transfer USDC fee
        uint256 remainder = minted - distributed;
        if (remainder != 0) t.safeTransfer(feeCollector, remainder);
        if (feeUSDC != 0) usdc.transfer(feeCollector, feeUSDC);
    }

    // ---- UUPS ----
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
