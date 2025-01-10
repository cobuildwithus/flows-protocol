// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { FlowTokenEmitter } from "../../src/token-issuance/FlowTokenEmitter.sol";
import { TokenEmitterETH } from "../../src/token-issuance/TokenEmitterETH.sol";
import { TokenEmitterERC20 } from "../../src/token-issuance/TokenEmitterERC20.sol";
import { ERC20VotesMintable } from "../../src/ERC20VotesMintable.sol";
import { ITokenEmitter } from "../../src/interfaces/ITokenEmitter.sol";
import { ProtocolRewards } from "../../src/protocol-rewards/ProtocolRewards.sol";
import { IWETH } from "../../src/interfaces/IWETH.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { RewardPool } from "../../src/RewardPool.sol";
import { BondingSCurve } from "../../src/token-issuance/BondingSCurve.sol";
import { MockWETH } from "../mocks/MockWETH.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";

// Optional Superfluid + Token imports if needed
import { SuperfluidFrameworkDeployer } from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";

/**
 * @title FlowTokenEmitterTest
 * @notice This test suite verifies the logic of FlowTokenEmitter, which allows buying with
 *         a payment token directly or bridging from ETH via an underlying TokenEmitterETH.
 */
contract FlowTokenEmitterTest is Test {
    using stdStorage for StdStorage;

    // ============ Contracts ============

    FlowTokenEmitter public flowTokenEmitter; // The contract under test
    TokenEmitterETH public ethEmitter; // The ETH emitter that sells the payment token
    TokenEmitterERC20 public underlyingERC20Emitter; // If needed for reference
    ERC20VotesMintable public brandToken; // The Flow / brand token sold by flowTokenEmitter
    ERC20VotesMintable public paymentToken; // The payment token that flowTokenEmitter expects
    MockWETH public weth;

    ProtocolRewards public protocolRewards;
    RewardPool public rewardPool; // For brandToken
    RewardPool public paymentRewardPool; // For paymentToken

    // Superfluid references if you need them
    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer internal deployer;
    SuperToken internal superToken;
    TestToken internal underlyingToken;

    // ============ Addresses ============
    address public owner;
    address public user1;
    address public user2;
    address public founderRewardAddress;
    address public protocolFeeRecipient;

    // ============ Bonding/VRGDA Parameters ============
    int256 public constant CURVE_STEEPNESS = int256(1e18) / 100;
    int256 public constant BASE_PRICE = int256(1e18) / 3000;
    int256 public constant MAX_PRICE_INCREASE = int256(1e18) / 300;
    int256 public constant SUPPLY_OFFSET = int256(1e18) * 1000;
    int256 public constant PRICE_DECAY_PERCENT = int256(1e18) / 2; // 50%
    int256 public constant PER_TIME_UNIT = int256(1e18) * 500; // 500 tokens/day
    uint256 public constant FOUNDER_REWARD_DURATION = 365 days * 5; // 5 years

    // Helper for founder reward calculation (7% or min=1)
    function getFounderReward(uint256 amount) public pure returns (uint256) {
        if (amount >= 14) {
            return (amount * 7) / 100; // 7%
        } else {
            return 1;
        }
    }

    // ============ Setup ============
    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        founderRewardAddress = makeAddr("founderRewardAddress");
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");

        // We do everything as owner initially
        vm.startPrank(owner);

        // 1) Deploy ProtocolRewards
        protocolRewards = new ProtocolRewards();

        // 2) Deploy WETH mock
        weth = new MockWETH();

        // 3) Deploy brand token (Flow token) + Payment token
        ERC20VotesMintable brandTokenImpl = new ERC20VotesMintable();
        ERC1967Proxy brandTokenProxy = new ERC1967Proxy(address(brandTokenImpl), "");
        brandToken = ERC20VotesMintable(address(brandTokenProxy));

        ERC20VotesMintable paymentTokenImpl = new ERC20VotesMintable();
        ERC1967Proxy paymentTokenProxy = new ERC1967Proxy(address(paymentTokenImpl), "");
        paymentToken = ERC20VotesMintable(address(paymentTokenProxy));

        // 4) Deploy two RewardPools (optional, to replicate your approach)
        RewardPool rewardPoolImpl = new RewardPool();
        ERC1967Proxy rewardPoolProxy = new ERC1967Proxy(address(rewardPoolImpl), "");
        rewardPool = RewardPool(address(rewardPoolProxy));

        RewardPool paymentRewardPoolImpl = new RewardPool();
        ERC1967Proxy paymentRewardPoolProxy = new ERC1967Proxy(address(paymentRewardPoolImpl), "");
        paymentRewardPool = RewardPool(address(paymentRewardPoolProxy));

        // 5) Deploy an ETH Emitter (TokenEmitterETH)
        TokenEmitterETH ethEmitterImpl = new TokenEmitterETH(address(protocolRewards), protocolFeeRecipient);
        ERC1967Proxy ethEmitterProxy = new ERC1967Proxy(address(ethEmitterImpl), "");
        ethEmitter = TokenEmitterETH(address(ethEmitterProxy));

        // 6) Deploy the FlowTokenEmitter (the bridging child)
        //    We'll do the same approach: behind a proxy
        FlowTokenEmitter flowEmitterImpl = new FlowTokenEmitter();
        ERC1967Proxy flowEmitterProxy = new ERC1967Proxy(address(flowEmitterImpl), "");
        flowTokenEmitter = FlowTokenEmitter(address(flowEmitterProxy));

        // 7) Initialize brandToken
        {
            address[] memory ignoreList = new address[](0);
            brandToken.initialize(
                owner, // initialOwner
                address(flowTokenEmitter), // set flowTokenEmitter as minter
                address(rewardPool),
                ignoreList,
                "Flow Brand Token",
                "FLOW"
            );
        }

        // 8) Initialize paymentToken
        {
            address[] memory ignoreList2 = new address[](0);
            paymentToken.initialize(
                owner,
                address(this),
                address(paymentRewardPool),
                ignoreList2,
                "Payment Token",
                "PAY"
            );
        }

        // Setup Superfluid
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
        deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();
        (underlyingToken, superToken) = deployer.deployWrapperSuperToken("Super Test Token", "STT", 18, 1e27, owner);

        // 9) Initialize the RewardPools
        //    We'll pass brandToken & flowTokenEmitter to rewardPool,
        //    pass paymentToken & ??? to paymentRewardPool if you want
        rewardPool.initialize(ISuperToken(address(superToken)), address(brandToken), address(flowTokenEmitter));
        paymentRewardPool.initialize(ISuperToken(address(superToken)), address(paymentToken), address(ethEmitter));

        // 10) Initialize the TokenEmitterETH
        ethEmitter.initialize({
            _initialOwner: owner,
            _erc20: address(paymentToken),
            _weth: address(weth),
            _founderRewardAddress: founderRewardAddress,
            _curveSteepness: CURVE_STEEPNESS,
            _basePrice: BASE_PRICE,
            _maxPriceIncrease: MAX_PRICE_INCREASE,
            _supplyOffset: SUPPLY_OFFSET,
            _priceDecayPercent: PRICE_DECAY_PERCENT,
            _perTimeUnit: PER_TIME_UNIT,
            _founderRewardDuration: FOUNDER_REWARD_DURATION
        });

        // 11) Finally, Initialize FlowTokenEmitter with bridging
        flowTokenEmitter.initialize(
            owner,
            address(brandToken),
            address(weth),
            founderRewardAddress,
            CURVE_STEEPNESS,
            BASE_PRICE,
            MAX_PRICE_INCREASE,
            SUPPLY_OFFSET,
            PRICE_DECAY_PERCENT,
            PER_TIME_UNIT,
            FOUNDER_REWARD_DURATION,
            address(paymentToken),
            address(ethEmitter)
        );

        vm.stopPrank();

        // 12) Set brandToken minter => flowTokenEmitter
        vm.prank(owner);
        brandToken.setMinter(address(flowTokenEmitter));

        // 13) Also set paymentToken minter => ethEmitter if you want the ETH emitter to mint payment tokens
        //     This line is crucial if your TokenEmitterETH is supposed to *mint* the paymentToken
        vm.prank(owner);
        paymentToken.setMinter(address(ethEmitter));

        // Provide user1 & user2 some initial ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Provide user1 & user2 some initial Payment Token if we want direct ERC20 flow
        // Mint more tokens to allow for larger purchases
        vm.startPrank(address(ethEmitter));
        paymentToken.mint(user1, 1000e18);
        paymentToken.mint(user2, 1000e18);
        vm.stopPrank();
    }

    // =========================================
    // ===========   Tests Begin   ============
    // =========================================

    function testInitialization() public {
        // Just check some basics
        assertEq(address(flowTokenEmitter.ethEmitter()), address(ethEmitter), "ETH emitter not set properly");
        assertEq(address(flowTokenEmitter.erc20()), address(brandToken), "Brand token not set");
        assertEq(address(flowTokenEmitter.paymentToken()), address(paymentToken), "Payment token not set");
    }

    /**
     * @notice Helper: buy Flow tokens directly with PaymentToken
     */
    function testBuyFlowWithPaymentToken() public {
        // user1 calls `buyToken(...)` on flowTokenEmitter (the normal ERC20 flow)
        address user = user1;
        // Reduce purchase amount to avoid insufficient funds
        uint256 flowAmount = 50e18;

        vm.startPrank(user);

        paymentToken.approve(address(flowTokenEmitter), type(uint256).max);

        // Let's get a quote
        (int256 costInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 cost = uint256(costInt);
        uint256 totalPayment = cost;

        ITokenEmitter.ProtocolRewardAddresses memory emptyAddr = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // We'll pass maxCost = totalPayment + 1 to allow small slippage
        uint256 maxCost = totalPayment + 1e18;

        // record balances
        uint256 userPAYBefore = paymentToken.balanceOf(user);
        uint256 brandBefore = brandToken.balanceOf(user);

        // buy
        flowTokenEmitter.buyToken(user, flowAmount, maxCost, emptyAddr);

        // check
        uint256 userPAYAfter = paymentToken.balanceOf(user);
        uint256 brandAfter = brandToken.balanceOf(user);
        assertEq(userPAYBefore - userPAYAfter, totalPayment, "User didn't pay correct totalPayment in PaymentToken");
        assertEq(brandAfter - brandBefore, flowAmount, "User didn't receive correct brand tokens");

        vm.stopPrank();
    }

    /**
     * @notice Helper: buy Flow tokens bridging from ETH => PaymentToken => Flow
     */
    function testBuyFlowViaETH() public {
        address user = user1;
        // Reduce purchase amount
        uint256 flowAmount = 20e18;

        vm.startPrank(user);

        // get a direct quote from flowTokenEmitter for brand tokens
        (int256 costInPAYInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 costInPAY = uint256(costInPAYInt);

        // then see how much ETH is needed to get costInPAY from `ethEmitter`
        (int256 costInETHInt, ) = ethEmitter.buyTokenQuoteWithRewards(costInPAY);
        uint256 costInETH = uint256(costInETHInt);

        // We'll pass maxCost = costInETH + 0.1 ether for reasonable slippage
        uint256 maxCost = costInETH + 0.1 ether;

        // record brand token & user ETH
        uint256 brandBefore = brandToken.balanceOf(user);
        uint256 userEthBefore = user.balance;

        ITokenEmitter.ProtocolRewardAddresses memory emptyAddr = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // call buyWithETH with smaller overpayment
        flowTokenEmitter.buyWithETH{ value: costInETH + 0.05 ether }(user, flowAmount, maxCost, emptyAddr);

        vm.stopPrank();

        // check brand token
        uint256 brandAfter = brandToken.balanceOf(user);
        assertEq(brandAfter - brandBefore, flowAmount, "Did not receive the correct Flow tokens");

        // check user's ETH used
        uint256 userEthAfter = user.balance;
        assertApproxEqAbs(userEthBefore - userEthAfter, costInETH, 1e14, "User didn't spend the correct ETH");
    }

    /**
     * @notice Tests bridging slippage: if costInETH exceeds maxCost
     */
    function testBuyFlowViaETH_SlippageRevert() public {
        address user = user1;
        // Reduce purchase amount
        uint256 flowAmount = 1000e18;

        // We'll get cost in PAY
        (int256 costInPAYInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 costInPAY = uint256(costInPAYInt);

        // We'll see how much ETH is needed
        (int256 costInETHInt, ) = ethEmitter.buyTokenQuoteWithRewards(costInPAY);
        uint256 costInETH = uint256(costInETHInt);

        // Ensure costInETH is large enough before subtracting
        require(costInETH > 0.1 ether, "costInETH too small for test");
        uint256 maxCost = costInETH - 0.1 ether;

        vm.startPrank(user);

        ITokenEmitter.ProtocolRewardAddresses memory emptyAddr = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        vm.expectRevert(ITokenEmitter.SLIPPAGE_EXCEEDED.selector);
        flowTokenEmitter.buyWithETH{ value: costInETH }(user, flowAmount, maxCost, emptyAddr);

        vm.stopPrank();
    }

    /**
     * @notice Tests bridging insufficient ETH
     */
    function testBuyFlowViaETH_InsufficientETH() public {
        address user = user1;
        // Reduce purchase amount
        uint256 flowAmount = 10e18;

        (int256 costInPAYInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 costInPAY = uint256(costInPAYInt);

        (int256 costInETHInt, ) = ethEmitter.buyTokenQuoteWithRewards(costInPAY);
        uint256 costInETH = uint256(costInETHInt);

        vm.startPrank(user);

        ITokenEmitter.ProtocolRewardAddresses memory emptyAddr = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        vm.expectRevert(ITokenEmitter.INSUFFICIENT_FUNDS.selector);
        flowTokenEmitter.buyWithETH{ value: costInETH / 2 }(user, flowAmount, costInETH, emptyAddr);

        vm.stopPrank();
    }

    /**
     * @notice Additional test: bridging founder reward
     */
    function testBuyFlowViaETH_FounderReward() public {
        address user = user1;
        // Keep flowAmount >= 14 for 7% founder reward
        uint256 flowAmount = 20e18;

        (int256 costInPAYInt, ) = flowTokenEmitter.buyTokenQuote(flowAmount);
        uint256 costInPAY = uint256(costInPAYInt);

        (int256 costInETHInt, ) = ethEmitter.buyTokenQuoteWithRewards(costInPAY);
        uint256 costInETH = uint256(costInETHInt);

        uint256 maxCost = costInETH + 0.1 ether;

        // record founder's brand token
        uint256 founderBefore = brandToken.balanceOf(founderRewardAddress);

        vm.startPrank(user1);
        ITokenEmitter.ProtocolRewardAddresses memory emptyAddr = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });
        flowTokenEmitter.buyWithETH{ value: costInETH }(user1, flowAmount, maxCost, emptyAddr);
        vm.stopPrank();

        uint256 founderAfter = brandToken.balanceOf(founderRewardAddress);
        uint256 expectedFounder = getFounderReward(flowAmount);

        assertEq(founderAfter - founderBefore, expectedFounder, "Founder reward mismatch in bridging scenario");
    }

    // ============ Utility ============

    /**
     * @notice If you want a direct function to do partial sells or more bridging tests,
     *         you can write them here.
     */
}
