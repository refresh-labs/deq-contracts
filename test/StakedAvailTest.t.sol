// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import {Test} from "lib/forge-std/src/Test.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20, StakedAvail} from "src/StakedAvail.sol";
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
        address withdrawalHelperImpl = address(new AvailWithdrawalHelper(avail));
        withdrawalHelper =
            AvailWithdrawalHelper(address(new TransparentUpgradeableProxy(withdrawalHelperImpl, msg.sender, "")));
        withdrawalHelper.initialize(msg.sender, stakedAvail, 1 ether);
        depository.initialize(msg.sender, bridge, msg.sender, bytes32(abi.encode(1)));
        stakedAvail.initialize(msg.sender, msg.sender, address(depository), withdrawalHelper);
    }

    function test_initialize() external view {
        assertEq(address(stakedAvail.avail()), address(avail));
        assertEq(stakedAvail.owner(), owner);
        assert(stakedAvail.hasRole(keccak256("UPDATER_ROLE"), owner));
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

    function testMint2(uint248 amountA, uint248 amountB) external {
        vm.assume(amountA != 0 && amountB != 0);
        // this is to prevent solidity from adding them as uint248
        uint256 amount1 = amountA;
        uint256 amount2 = amountB;
        address from = makeAddr("from");
        vm.startPrank(from);
        avail.mint(from, amount1 + amount2);
        avail.approve(address(stakedAvail), amount1 + amount2);
        stakedAvail.mint(amount1);
        assertEq(stakedAvail.balanceOf(from), amount1);
        assertEq(stakedAvail.assets(), amount1);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount1);
        stakedAvail.mint(amount2);
        assertEq(stakedAvail.balanceOf(from), amount1 + amount2);
        assertEq(stakedAvail.assets(), amount1 + amount2);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount1 + amount2);
    }

    function testMint3(uint248 amountA, uint248 amountB, int248 rand) external {
        vm.assume(amountA != 0 && amountB != 0 && rand > 0);
        // this is to prevent solidity from adding them as uint248
        uint256 amount1 = amountA;
        uint256 amount2 = amountB;
        uint256 random = uint256(int256(rand));
        address from = makeAddr("from");
        vm.startPrank(from);
        avail.mint(from, amount1 + amount2);
        avail.approve(address(stakedAvail), amount1 + amount2);
        stakedAvail.mint(amount1);
        assertEq(stakedAvail.balanceOf(from), amount1);
        assertEq(stakedAvail.assets(), amount1);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount1);
        vm.startPrank(owner);
        // inflate value of stAVAIL
        stakedAvail.updateAssets(int256(random));
        vm.startPrank(from);
        stakedAvail.mint(amount2);
        assertLt(stakedAvail.balanceOf(from), amount1 + amount2);
        assertEq(stakedAvail.assets(), amount1 + random + amount2);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount1 + amount2);
    }

    function testMint4(uint248 amountA, uint248 amountB) external {
        // we add a decent chunk of amountB otherwise it has no effect on deflated amount
        vm.assume(amountA >= 2 && amountB > 2);
        // this is to prevent solidity from adding them as uint248
        uint256 amount1 = uint256(amountA);
        uint256 amount2 = uint256(amountB);
        address from = makeAddr("from");
        vm.startPrank(from);
        avail.mint(from, amount1 + amount2);
        avail.approve(address(stakedAvail), amount1 + amount2);
        stakedAvail.mint(amount1);
        uint256 prevBalance = stakedAvail.balanceOf(from);
        assertEq(stakedAvail.balanceOf(from), amount1);
        assertEq(stakedAvail.assets(), amount1);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount1);
        vm.startPrank(owner);
        uint256 reduction = amount1 / 2;
        // deflate value of stAVAIL
        stakedAvail.updateAssets(-int256(amount1 / 2));
        vm.startPrank(from);
        stakedAvail.mint(amount2);
        uint256 diffBalance = stakedAvail.balanceOf(from) - prevBalance;
        assertGt(diffBalance, amount2);
        assertEq(stakedAvail.assets(), amount1 + amount2 - reduction);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount1 + amount2);
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
        vm.assume(amount != 0 && amount >= withdrawalHelper.minWithdrawal() && amount < type(uint256).max);
        address from = makeAddr("from");
        vm.startPrank(from);
        avail.mint(from, amount);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        assertEq(stakedAvail.balanceOf(from), amount);
        assertEq(stakedAvail.assets(), amount);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount);
        stakedAvail.burn(amount);
        assertEq(withdrawalHelper.withdrawalAmounts(1), amount);
        assertEq(withdrawalHelper.ownerOf(1), from);
        assertEq(stakedAvail.balanceOf(from), 0);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount);
    }

    function testBurn2(uint256 amount, uint256 burnAmt) external {
        // the < is needed because it overflows our exchange rate calculation otherwise
        vm.assume(
            amount != 0 && burnAmt >= withdrawalHelper.minWithdrawal() && amount < type(uint256).max
                && burnAmt <= amount
        );
        address from = makeAddr("from");
        vm.startPrank(from);
        avail.mint(from, amount);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        assertEq(stakedAvail.balanceOf(from), amount);
        assertEq(stakedAvail.assets(), amount);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount);
        stakedAvail.burn(burnAmt);
        assertEq(withdrawalHelper.withdrawalAmounts(1), burnAmt);
        assertEq(withdrawalHelper.ownerOf(1), from);
        assertEq(stakedAvail.balanceOf(from), amount - burnAmt);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount);
    }

    function testBurn3(uint256 amount, uint248 burnAmtA, uint248 burnAmtB) external {
        uint256 burnAmt1 = uint256(burnAmtA);
        uint256 burnAmt2 = uint256(burnAmtB);
        // the < is needed because it overflows our exchange rate calculation otherwise
        vm.assume(
            amount != 0 && burnAmtA > withdrawalHelper.minWithdrawal() && burnAmtB > withdrawalHelper.minWithdrawal()
                && amount < type(uint256).max && (burnAmt1 + burnAmt2) < amount
        );
        address from = makeAddr("from");
        vm.startPrank(from);
        avail.mint(from, amount);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        assertEq(stakedAvail.balanceOf(from), amount);
        assertEq(stakedAvail.assets(), amount);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount);
        stakedAvail.burn(burnAmtA);
        assertEq(withdrawalHelper.withdrawalAmounts(1), burnAmt1);
        assertEq(withdrawalHelper.ownerOf(1), from);
        assertEq(stakedAvail.balanceOf(from), amount - burnAmt1);
        stakedAvail.burn(burnAmtB);
        // burning inflates the value of stAVL
        assertGe(withdrawalHelper.withdrawalAmounts(2), burnAmt2);
        assertEq(withdrawalHelper.ownerOf(2), from);
        assertEq(stakedAvail.balanceOf(from), amount - burnAmt1 - burnAmt2);
    }

    function testMintAndBurnTwice(uint248 mintAmt, uint248 burnAmt) external {
        vm.assume(mintAmt != 0 && burnAmt >= withdrawalHelper.minWithdrawal() && burnAmt <= mintAmt);
        address from = makeAddr("from");
        vm.startPrank(from);
        avail.mint(from, mintAmt);
        avail.approve(address(stakedAvail), mintAmt);
        stakedAvail.mint(mintAmt);
        assertEq(stakedAvail.balanceOf(from), mintAmt);
        assertEq(stakedAvail.assets(), mintAmt);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), mintAmt);
        stakedAvail.burn(burnAmt);
        assertEq(withdrawalHelper.withdrawalAmounts(1), burnAmt);
        assertEq(withdrawalHelper.ownerOf(1), from);
        assertEq(stakedAvail.balanceOf(from), mintAmt - burnAmt);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), mintAmt);
        avail.mint(from, mintAmt);
        avail.approve(address(stakedAvail), mintAmt);
        vm.expectEmit(true, true, false, true, address(stakedAvail));
        emit IERC20.Transfer(address(0), from, mintAmt);
        stakedAvail.mint(mintAmt);
        assertEq(stakedAvail.balanceOf(from), uint256(uint256(mintAmt) * 2) - uint256(burnAmt));
        assertEq(stakedAvail.assets(), (mintAmt * 2));
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), mintAmt);
        stakedAvail.burn(burnAmt);
        assertEq(withdrawalHelper.withdrawalAmounts(2), burnAmt);
        assertEq(withdrawalHelper.ownerOf(2), from);
        assertEq(stakedAvail.balanceOf(from), mintAmt - burnAmt);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), burnAmt);
    }
}
