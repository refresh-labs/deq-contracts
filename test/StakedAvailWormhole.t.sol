// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {StakedAvailWormhole} from "src/StakedAvailWormhole.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Vm, Test} from "forge-std/Test.sol";

contract StakedAvailWormholeTest is Test {
    StakedAvailWormhole stavail;
    address owner;
    address governance;
    address minter;
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function setUp() external {
        governance = makeAddr("governance");
        minter = makeAddr("minter");
        address impl = address(new StakedAvailWormhole());
        stavail = StakedAvailWormhole(address(new TransparentUpgradeableProxy(impl, msg.sender, "")));
        stavail.initialize(governance);
        vm.prank(governance);
        stavail.grantRole(MINTER_ROLE, minter);
    }

    function testRevert_initialize(address rand) external {
        vm.expectRevert();
        stavail.initialize(rand);
    }

    function test_initialize() external view {
        assertEq(stavail.totalSupply(), 0);
        assertNotEq(stavail.owner(), address(0));
        assertEq(stavail.owner(), governance);
        assertNotEq(stavail.name(), "");
        assertEq(stavail.name(), "Staked Avail (Wormhole)");
        assertNotEq(stavail.symbol(), "");
        assertEq(stavail.symbol(), "stAVAIL.W");
    }

    function testRevertOnlyMinter_mint(address to, uint256 amount) external {
        address rand = makeAddr("rand");
        vm.assume(rand != minter);
        vm.expectRevert(
            abi.encodeWithSelector((IAccessControl.AccessControlUnauthorizedAccount.selector), rand, MINTER_ROLE)
        );
        vm.prank(rand);
        stavail.mint(to, amount);
    }

    function test_mint(address to, uint256 amount) external {
        vm.assume(to != address(0));
        vm.prank(minter);
        stavail.mint(to, amount);
        assertEq(stavail.balanceOf(to), amount);
    }

    function test_burn(address from, uint256 amount) external {
        vm.assume(from != address(0));
        vm.prank(minter);
        stavail.mint(from, amount);
        assertEq(stavail.balanceOf(from), amount);
        vm.prank(from);
        stavail.burn(amount);
        assertEq(stavail.balanceOf(from), 0);
    }

    function test_burn2(address from, uint256 amount, uint256 amount2) external {
        vm.assume(from != address(0) && amount2 < amount);
        vm.prank(minter);
        stavail.mint(from, amount);
        assertEq(stavail.balanceOf(from), amount);
        vm.prank(from);
        stavail.burn(amount2);
        assertEq(stavail.balanceOf(from), amount - amount2);
    }
}
