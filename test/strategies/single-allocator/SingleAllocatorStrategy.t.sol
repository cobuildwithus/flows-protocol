// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";

import { SingleAllocatorStrategy } from "../../../src/allocation-strategies/SingleAllocatorStrategy.sol";
import { IAllocationStrategy } from "../../../src/interfaces/IAllocationStrategy.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SingleAllocatorStrategyTest is Test {
    address internal _owner = address(0xA11CE);
    address internal _allocator = address(0xB0B);
    address internal _attacker = address(0xBAD);
    address internal _newAllocator = address(0xCAFE);

    SingleAllocatorStrategy internal _strategy;
    ERC1967Proxy internal _proxy;

    function setUp() public {
        // Deploy implementation
        SingleAllocatorStrategy impl = new SingleAllocatorStrategy();

        // Deploy proxy with empty data (initializer called later)
        _proxy = new ERC1967Proxy(address(impl), "");

        // Cast proxy address to strategy interface
        _strategy = SingleAllocatorStrategy(address(_proxy));

        // Initialize via owner
        vm.prank(_owner);
        _strategy.initialize(_owner, _allocator);
    }

    /* ─────────────────────────────────────────────
        Initialization
    ───────────────────────────────────────────── */

    function testInitializeSetsState() public {
        assertEq(_strategy.allocator(), _allocator);
        assertEq(_strategy.owner(), _owner);
    }

    function testInitializeZeroAllocatorReverts() public {
        SingleAllocatorStrategy impl = new SingleAllocatorStrategy();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        SingleAllocatorStrategy strat = SingleAllocatorStrategy(address(proxy));

        vm.prank(_owner);
        vm.expectRevert(IAllocationStrategy.ADDRESS_ZERO.selector);
        strat.initialize(_owner, address(0));
    }

    function testInitializeOnlyOnce() public {
        vm.prank(_owner);
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        _strategy.initialize(_owner, _allocator);
    }

    /* ─────────────────────────────────────────────
        Pure / view behaviour
    ───────────────────────────────────────────── */

    function testAllocationKeyAlwaysZero() public {
        assertEq(_strategy.allocationKey(address(0x1), ""), 0);
        assertEq(_strategy.allocationKey(address(0x2), abi.encode(123)), 0);
    }

    function testCurrentWeightReturnsVirtualWeight() public {
        uint256 expected = _strategy.VIRTUAL_WEIGHT();
        assertEq(_strategy.currentWeight(0), expected);
        assertEq(_strategy.currentWeight(type(uint256).max), expected);
    }

    function testTotalAllocationWeightIsZero() public {
        assertEq(_strategy.totalAllocationWeight(), 0);
    }

    /* ─────────────────────────────────────────────
        Permissioning & allocator logic
    ───────────────────────────────────────────── */

    function testCanAllocateTrueForAllocator() public {
        assertTrue(_strategy.canAllocate(0, _allocator));
    }

    function testCanAllocateFalseForOthers() public {
        assertFalse(_strategy.canAllocate(0, _attacker));
    }

    function testChangeAllocatorByOwner() public {
        vm.prank(_owner);
        _strategy.changeAllocator(_newAllocator);

        assertEq(_strategy.allocator(), _newAllocator);
        assertTrue(_strategy.canAllocate(0, _newAllocator));
        assertFalse(_strategy.canAllocate(0, _allocator));
    }

    function testChangeAllocatorOnlyOwner() public {
        vm.prank(_attacker);
        vm.expectRevert();
        _strategy.changeAllocator(_newAllocator);
    }

    function testChangeAllocatorZeroReverts() public {
        vm.prank(_owner);
        vm.expectRevert(bytes("new allocator: zero"));
        _strategy.changeAllocator(address(0));
    }

    /* ─────────────────────────────────────────────
        UUPS upgrade authorization
    ───────────────────────────────────────────── */

    function testUpgradeToByOwner() public {
        // deploy fresh implementation to upgrade to
        SingleAllocatorStrategy newImpl = new SingleAllocatorStrategy();

        vm.prank(_owner);
        _strategy.upgradeTo(address(newImpl));

        // basic sanity: allocator value should persist
        assertEq(_strategy.allocator(), _allocator);
        // and canAllocate should still work
        assertTrue(_strategy.canAllocate(0, _allocator));
    }

    function testUpgradeToByNonOwnerReverts() public {
        SingleAllocatorStrategy newImpl = new SingleAllocatorStrategy();
        vm.prank(_attacker);
        vm.expectRevert();
        _strategy.upgradeTo(address(newImpl));
    }
}
