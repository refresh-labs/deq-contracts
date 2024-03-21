// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import {Test} from "lib/forge-std/src/Test.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {StakedAvail} from "src/StakedAvail.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {AvailDepository} from "src/AvailDepository.sol";
import {MockAvailBridge} from "src/mocks/MockAvailBridge.sol";
import {IAvailBridge} from "src/interfaces/IAvailBridge.sol";
import {AvailWithdrawalHelper} from "src/AvailWithdrawalHelper.sol";
import {console} from "lib/forge-std/src/console.sol";

contract StakedAvailTest is Test {
    StakedAvail public stakedAvail;
    MockERC20 public avail;
    AvailDepository public depository;
    IAvailBridge public bridge;
    AvailWithdrawalHelper public withdrawalHelper;
    address owner;

    function setUp() external {
        owner = msg.sender;
        avail = new MockERC20("Avail", "AVAIL");
        bridge = IAvailBridge(address(new MockAvailBridge()));
        address impl = address(new StakedAvail(avail));
        stakedAvail = StakedAvail(address(new TransparentUpgradeableProxy(impl, msg.sender, "")));
        address depositoryImpl = address(new AvailDepository(avail));
        depository = AvailDepository(address(new TransparentUpgradeableProxy(depositoryImpl, msg.sender, "")));
        address withdrawalHelperImpl = address(new AvailWithdrawalHelper());
        withdrawalHelper = AvailWithdrawalHelper(address(new TransparentUpgradeableProxy(withdrawalHelperImpl, msg.sender, "")));
        withdrawalHelper.initialize(avail, stakedAvail, 1 ether, msg.sender);
        depository.initialize(msg.sender, bridge, msg.sender, bytes32(abi.encode(1)));
        stakedAvail.initialize(msg.sender, msg.sender, address(depository), withdrawalHelper);
    }

    function test_initialize() external view {
        assertEq(address(stakedAvail.avail()), address(avail));
        assertEq(stakedAvail.owner(), owner);
        assertEq(stakedAvail.updater(), owner);
        assertEq(stakedAvail.depository(), address(depository));
        assertEq(address(stakedAvail.withdrawalHelper()), address(withdrawalHelper));
    }

    function testMint(uint256 amount) external {
        vm.assume(amount != 0);
        address from = makeAddr("from");
        vm.startPrank(from);
        avail.mint(from, amount);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        assertEq(stakedAvail.balanceOf(from), amount);
        assertEq(stakedAvail.assets(), amount);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount);
    }

    function testMintTo(uint256 amount) external {
        vm.assume(amount != 0);
        address from = makeAddr("from");
        address to = makeAddr("to");
        vm.startPrank(from);
        avail.mint(from, amount);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mintTo(to, amount);
        assertEq(stakedAvail.balanceOf(to), amount);
        assertEq(stakedAvail.assets(), amount);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount);
    }

    function testBurn(uint256 amount) external {
        // the < is needed because it overflows our exchange rate calculation otherwise
        vm.assume(amount != 0 && amount > withdrawalHelper.minWithdrawal() && amount < type(uint256).max);
        console.log("amount", amount);
        console.log("lastTokenId", withdrawalHelper.lastTokenId());
        address from = makeAddr("from");
        vm.startPrank(from);
        avail.mint(from, amount);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        stakedAvail.burn(amount);
        console.log("lastTokenId", withdrawalHelper.lastTokenId());
        assertEq(withdrawalHelper.withdrawalAmounts(1), amount);
        assertEq(withdrawalHelper.ownerOf(1), from);
        assertEq(stakedAvail.balanceOf(from), 0);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount);
    }
}
