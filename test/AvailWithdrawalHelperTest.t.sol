// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {Test} from "lib/forge-std/src/Test.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20, IStakedAvail, StakedAvail} from "src/StakedAvail.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {AvailDepository} from "src/AvailDepository.sol";
import {MockAvailBridge} from "src/mocks/MockAvailBridge.sol";
import {IAvailBridge} from "src/interfaces/IAvailBridge.sol";
import {IAvailWithdrawalHelper, AvailWithdrawalHelper} from "src/AvailWithdrawalHelper.sol";
import {console} from "lib/forge-std/src/console.sol";

contract AvailWithdrawalHelperTest is Test {
    StakedAvail public stakedAvail;
    MockERC20 public avail;
    AvailDepository public depository;
    IAvailBridge public bridge;
    AvailWithdrawalHelper public withdrawalHelper;
    address owner;

    function setUp() external {
        owner = msg.sender;
        avail = new MockERC20("Avail", "AVAIL");
        bridge = IAvailBridge(address(new MockAvailBridge(avail)));
        address impl = address(new StakedAvail(avail));
        stakedAvail = StakedAvail(address(new TransparentUpgradeableProxy(impl, msg.sender, "")));
        address depositoryImpl = address(new AvailDepository(avail, bridge));
        depository = AvailDepository(address(new TransparentUpgradeableProxy(depositoryImpl, msg.sender, "")));
        address withdrawalHelperImpl = address(new AvailWithdrawalHelper(avail));
        withdrawalHelper =
            AvailWithdrawalHelper(address(new TransparentUpgradeableProxy(withdrawalHelperImpl, msg.sender, "")));
        withdrawalHelper.initialize(msg.sender, stakedAvail, 1 ether);
        depository.initialize(msg.sender, msg.sender, bytes32(abi.encode(1)));
        stakedAvail.initialize(msg.sender, msg.sender, address(depository), withdrawalHelper);
    }

    function testRevert_constructor() external {
        vm.expectRevert(IAvailWithdrawalHelper.ZeroAddress.selector);
        new AvailWithdrawalHelper(IERC20(address(0)));
    }

    function test_constructor(address rand) external {
        vm.assume(rand != address(0));
        AvailWithdrawalHelper newWithdrawalHelper = new AvailWithdrawalHelper(IERC20(rand));
        assertEq(address(newWithdrawalHelper.avail()), rand);
    }

    function testRevert_initialize(address rand, address newGovernance, address newStakedAvail, uint256 amount)
        external
    {
        vm.assume(rand != address(0));
        AvailWithdrawalHelper newWithdrawalHelper = new AvailWithdrawalHelper(IERC20(rand));
        assertEq(address(newWithdrawalHelper.avail()), rand);
        vm.assume(newGovernance == address(0) || newStakedAvail == address(0));
        vm.expectRevert(IAvailWithdrawalHelper.ZeroAddress.selector);
        newWithdrawalHelper.initialize(newGovernance, IStakedAvail(newStakedAvail), amount);
    }

    function test_initialize() external view {
        assertEq(address(withdrawalHelper.avail()), address(avail));
        assertEq(address(withdrawalHelper.stAvail()), address(stakedAvail));
        assertEq(withdrawalHelper.lastTokenId(), 0);
        assertEq(withdrawalHelper.withdrawalAmount(), 0);
        assertEq(withdrawalHelper.lastFulfillment(), 0);
        assertEq(withdrawalHelper.owner(), owner);
        assertEq(withdrawalHelper.minWithdrawal(), 1 ether);
        assertTrue(withdrawalHelper.supportsInterface(0x01ffc9a7));
    }

    function testRevertOnlyStakedAvail_mint(address account, uint256 amount, uint256 shares) external {
        vm.expectRevert(IAvailWithdrawalHelper.OnlyStakedAvail.selector);
        withdrawalHelper.mint(account, amount, shares);
    }

    function testRevertInvalidWithdrawalAmount_mint(address account, uint256 amount, uint256 shares) external {
        vm.assume(amount < withdrawalHelper.minWithdrawal());
        vm.prank(address(stakedAvail));
        vm.expectRevert(IAvailWithdrawalHelper.InvalidWithdrawalAmount.selector);
        withdrawalHelper.mint(account, amount, shares);
    }

    function test_mint(address account, uint256 amount, uint256 shares) external {
        vm.assume(amount > withdrawalHelper.minWithdrawal() && account != address(0));
        vm.prank(address(stakedAvail));
        withdrawalHelper.mint(account, amount, shares);
        (uint256 amt, uint256 shrs) = withdrawalHelper.getWithdrawal(1);
        assertEq(withdrawalHelper.withdrawalAmount(), amount);
        assertEq(withdrawalHelper.lastTokenId(), 1);
        assertEq(amount, amt);
        assertEq(shares, shrs);
        assertEq(withdrawalHelper.previewFulfill(1), amount);
    }

    function test_mintTwice(address account, uint248 amount, uint248 shares) external {
        vm.assume(amount > withdrawalHelper.minWithdrawal() && account != address(0));
        vm.startPrank(address(stakedAvail));
        withdrawalHelper.mint(account, amount, shares);
        withdrawalHelper.mint(account, amount, shares);
        (uint256 amt1, uint256 shrs1) = withdrawalHelper.getWithdrawal(1);
        (uint256 amt2, uint256 shrs2) = withdrawalHelper.getWithdrawal(1);
        assertEq(withdrawalHelper.withdrawalAmount(), uint256(amount) * 2);
        assertEq(withdrawalHelper.lastTokenId(), 2);
        assertEq(amt1, amount);
        assertEq(shrs1, shares);
        assertEq(amt2, amount);
        assertEq(shrs2, shares);
        assertEq(withdrawalHelper.previewFulfill(2), uint256(amount) * 2);
    }

    function testRevertNotFulfilled_burn(address account, uint256 amount, uint256 shares) external {
        vm.assume(amount > withdrawalHelper.minWithdrawal() && account != address(0));
        vm.prank(address(stakedAvail));
        withdrawalHelper.mint(account, amount, shares);
        vm.expectRevert(IAvailWithdrawalHelper.NotFulfilled.selector);
        withdrawalHelper.burn(1);
    }

    function test_burn(uint248 amount) external {
        vm.assume(amount > withdrawalHelper.minWithdrawal());
        address from = makeAddr("from");
        avail.mint(from, amount);
        vm.startPrank(from);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        stakedAvail.burn(amount);
        avail.mint(address(withdrawalHelper), amount);
        (uint256 amt1, uint256 shrs1) = withdrawalHelper.getWithdrawal(1);
        assertEq(amt1, amount);
        assertEq(shrs1, amount);
        withdrawalHelper.burn(1);
        assertEq(withdrawalHelper.withdrawalAmount(), 0);
        assertEq(withdrawalHelper.lastFulfillment(), 1);
        assertEq(withdrawalHelper.previewFulfill(1), 0);
        assertEq(avail.balanceOf(from), amount);
        assertEq(stakedAvail.balanceOf(from), 0);
        assertEq(stakedAvail.balanceOf(address(stakedAvail)), 0);
        assertEq(stakedAvail.totalSupply(), 0);
        assertEq(stakedAvail.assets(), 0);
    }

    function test_burnTwice(uint128 amount128, uint128 burnAmount128) external {
        uint256 amount = uint256(amount128);
        uint256 burnAmount = uint256(burnAmount128);
        vm.assume(
            amount > burnAmount && (amount - burnAmount) > withdrawalHelper.minWithdrawal()
                && burnAmount > withdrawalHelper.minWithdrawal()
        );
        address from = makeAddr("from");
        avail.mint(from, amount);
        vm.startPrank(from);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        stakedAvail.burn(amount - burnAmount);
        avail.mint(address(withdrawalHelper), amount);
        (uint256 amt2, uint256 shrs2) = withdrawalHelper.getWithdrawal(1);
        assertEq(amt2, amount - burnAmount);
        assertEq(shrs2, amount - burnAmount);
        withdrawalHelper.burn(1);
        assertEq(withdrawalHelper.withdrawalAmount(), 0);
        assertEq(withdrawalHelper.lastFulfillment(), 1);
        assertEq(withdrawalHelper.previewFulfill(1), 0);
        assertEq(avail.balanceOf(from), amount - burnAmount);
        assertEq(stakedAvail.balanceOf(from), burnAmount);
        assertEq(stakedAvail.balanceOf(address(stakedAvail)), 0);
        assertEq(stakedAvail.totalSupply(), burnAmount);
        assertEq(stakedAvail.assets(), burnAmount);
        stakedAvail.burn(burnAmount);
        withdrawalHelper.burn(2);
        assertEq(withdrawalHelper.withdrawalAmount(), 0);
        assertEq(withdrawalHelper.lastFulfillment(), 2);
        assertEq(withdrawalHelper.previewFulfill(2), 0);
        assertEq(stakedAvail.balanceOf(from), 0);
        assertEq(stakedAvail.balanceOf(address(stakedAvail)), 0);
        assertEq(stakedAvail.totalSupply(), 0);
        assertEq(stakedAvail.assets(), 0);
    }

    function test_scenarioQueue1(uint128 amountA, uint64 burnA, uint64 burnB, uint64 burnC) external {
        uint256 amount = uint256(amountA);
        uint256 burn1 = uint256(burnA);
        uint256 burn2 = uint256(burnB);
        uint256 burn3 = uint256(burnC);
        vm.assume(
            amount >= (burn1 + burn2 + burn3) && burn1 > withdrawalHelper.minWithdrawal()
                && burn2 > withdrawalHelper.minWithdrawal() && burn3 > withdrawalHelper.minWithdrawal()
        );
        address from = makeAddr("from");
        avail.mint(from, amount);
        vm.startPrank(from);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        stakedAvail.burn(burn1);
        stakedAvail.burn(burn2);
        stakedAvail.burn(burn3);
        avail.mint(address(withdrawalHelper), burn1 + burn2);
        vm.expectRevert(IAvailWithdrawalHelper.NotFulfilled.selector);
        withdrawalHelper.burn(3);
        withdrawalHelper.burn(2);
        assertEq(withdrawalHelper.withdrawalAmount(), burn1 + burn3);
        assertEq(withdrawalHelper.lastFulfillment(), 2);
        assertEq(withdrawalHelper.previewFulfill(2), 0);
        assertEq(avail.balanceOf(from), burn2);
        vm.expectRevert(IAvailWithdrawalHelper.NotFulfilled.selector);
        withdrawalHelper.burn(3);
        withdrawalHelper.burn(1);
        assertEq(withdrawalHelper.withdrawalAmount(), burn3);
        assertEq(withdrawalHelper.lastFulfillment(), 2);
        assertEq(withdrawalHelper.previewFulfill(3), burn3);
        avail.mint(address(withdrawalHelper), burn3);
        withdrawalHelper.burn(3);
        assertEq(withdrawalHelper.withdrawalAmount(), 0);
        assertEq(withdrawalHelper.lastFulfillment(), 3);
        assertEq(withdrawalHelper.previewFulfill(3), 0);
    }

    function test_scenarioQueue2(uint128 amountA, uint64 burnA, uint64 burnB, uint64 burnC) external {
        uint256 amount = uint256(amountA);
        uint256 burn1 = uint256(burnA);
        uint256 burn2 = uint256(burnB);
        uint256 burn3 = uint256(burnC);
        vm.assume(
            amount >= (burn1 + burn2 + burn3) && burn1 > withdrawalHelper.minWithdrawal()
                && burn2 > withdrawalHelper.minWithdrawal() && burn3 > withdrawalHelper.minWithdrawal()
        );
        address from = makeAddr("from");
        avail.mint(from, amount);
        vm.startPrank(from);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        stakedAvail.burn(burn1);
        stakedAvail.burn(burn2);
        stakedAvail.burn(burn3);
        avail.mint(address(withdrawalHelper), burn1 + burn2 + burn3);
        withdrawalHelper.burn(1);
        withdrawalHelper.burn(2);
        withdrawalHelper.burn(3);
        assertEq(withdrawalHelper.withdrawalAmount(), 0);
        assertEq(withdrawalHelper.lastFulfillment(), 3);
        assertEq(withdrawalHelper.previewFulfill(3), 0);
    }

    function test_scenarioQueue3(uint128 amountA, uint64 burnA, uint64 burnB, uint64 burnC) external {
        uint256 amount = uint256(amountA);
        uint256 burn1 = uint256(burnA);
        uint256 burn2 = uint256(burnB);
        uint256 burn3 = uint256(burnC);
        vm.assume(
            amount >= (burn1 + burn2 + burn3) && burn1 > withdrawalHelper.minWithdrawal()
                && burn2 > withdrawalHelper.minWithdrawal() && burn3 > withdrawalHelper.minWithdrawal()
        );
        address from = makeAddr("from");
        avail.mint(from, amount);
        vm.startPrank(from);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        stakedAvail.burn(burn1);
        stakedAvail.burn(burn2);
        stakedAvail.burn(burn3);
        avail.mint(address(withdrawalHelper), burn1 + burn2 + burn3);
        withdrawalHelper.burn(3);
        withdrawalHelper.burn(2);
        withdrawalHelper.burn(1);
    }

    function test_scenarioQueue4(uint128 amountA, uint64 burnA, uint64 burnB, uint64 burnC) external {
        uint256 amount = uint256(amountA);
        uint256 burn1 = uint256(burnA);
        uint256 burn2 = uint256(burnB);
        uint256 burn3 = uint256(burnC);
        vm.assume(
            amount >= (burn1 + burn2 + burn3) && burn1 > withdrawalHelper.minWithdrawal()
                && burn2 > withdrawalHelper.minWithdrawal() && burn3 > withdrawalHelper.minWithdrawal()
        );
        address from = makeAddr("from");
        avail.mint(from, amount);
        vm.startPrank(from);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        stakedAvail.burn(burn1);
        stakedAvail.burn(burn2);
        stakedAvail.burn(burn3);
        avail.mint(address(withdrawalHelper), burn1);
        vm.expectRevert(IAvailWithdrawalHelper.NotFulfilled.selector);
        withdrawalHelper.burn(3);
        vm.expectRevert(IAvailWithdrawalHelper.NotFulfilled.selector);
        withdrawalHelper.burn(2);
        withdrawalHelper.burn(1);
        assertEq(withdrawalHelper.withdrawalAmount(), burn2 + burn3);
        assertEq(withdrawalHelper.lastFulfillment(), 1);
        assertEq(withdrawalHelper.previewFulfill(1), 0);
        avail.mint(address(withdrawalHelper), burn2);
        withdrawalHelper.burn(2);
        assertEq(withdrawalHelper.withdrawalAmount(), burn3);
        assertEq(withdrawalHelper.lastFulfillment(), 2);
        assertEq(withdrawalHelper.previewFulfill(2), 0);
        avail.mint(address(withdrawalHelper), burn3);
        withdrawalHelper.burn(3);
        assertEq(withdrawalHelper.withdrawalAmount(), 0);
        assertEq(withdrawalHelper.lastFulfillment(), 3);
        assertEq(withdrawalHelper.previewFulfill(3), 0);
    }

    function test_scenarioQueue5() external {
        address from = makeAddr("from");
        avail.mint(from, 1000 ether);
        vm.startPrank(from);
        avail.approve(address(stakedAvail), 1000 ether);
        stakedAvail.mint(1000 ether);
        stakedAvail.burn(100 ether);
        stakedAvail.burn(200 ether);
        stakedAvail.burn(100 ether);
        stakedAvail.burn(300 ether);
        stakedAvail.burn(300 ether);
        avail.mint(address(withdrawalHelper), 300 ether); // 300 ether, fulfil to 2
        vm.expectRevert(IAvailWithdrawalHelper.NotFulfilled.selector);
        withdrawalHelper.burn(3);
        vm.expectRevert(IAvailWithdrawalHelper.NotFulfilled.selector);
        withdrawalHelper.burn(4);
        vm.expectRevert(IAvailWithdrawalHelper.NotFulfilled.selector);
        withdrawalHelper.burn(5);
        withdrawalHelper.burn(2);
        assertEq(withdrawalHelper.withdrawalAmount(), 800 ether);
        assertEq(withdrawalHelper.lastFulfillment(), 2);
        assertEq(withdrawalHelper.previewFulfill(2), 0);
        avail.mint(address(withdrawalHelper), 400 ether); // 700 ether, fulfil to 4
        vm.expectRevert(IAvailWithdrawalHelper.NotFulfilled.selector);
        withdrawalHelper.burn(5);
        withdrawalHelper.burn(3);
        withdrawalHelper.burn(1);
        assertEq(withdrawalHelper.withdrawalAmount(), 600 ether);
        assertEq(withdrawalHelper.lastFulfillment(), 3);
        assertEq(withdrawalHelper.previewFulfill(3), 0);
        avail.mint(address(withdrawalHelper), 200 ether); // 900 ether, fulfil to 4
        vm.expectRevert(IAvailWithdrawalHelper.NotFulfilled.selector);
        withdrawalHelper.burn(5);
        avail.mint(address(withdrawalHelper), 200 ether); // 1000 ether, fulfil to 5
        withdrawalHelper.burn(5);
        assertEq(withdrawalHelper.withdrawalAmount(), 300 ether);
        assertEq(withdrawalHelper.lastFulfillment(), 5);
        assertEq(withdrawalHelper.previewFulfill(5), 0);
        withdrawalHelper.burn(4);
        assertEq(withdrawalHelper.withdrawalAmount(), 0);
        assertEq(withdrawalHelper.lastFulfillment(), 5);
        assertEq(withdrawalHelper.previewFulfill(5), 0);
        assertEq(withdrawalHelper.remainingFulfillment(), 0);
    }
}
