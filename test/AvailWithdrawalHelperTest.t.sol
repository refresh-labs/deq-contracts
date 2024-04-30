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
        address depositoryImpl = address(new AvailDepository(avail));
        depository = AvailDepository(address(new TransparentUpgradeableProxy(depositoryImpl, msg.sender, "")));
        address withdrawalHelperImpl = address(new AvailWithdrawalHelper(avail));
        withdrawalHelper =
            AvailWithdrawalHelper(address(new TransparentUpgradeableProxy(withdrawalHelperImpl, msg.sender, "")));
        withdrawalHelper.initialize(msg.sender, stakedAvail, 1 ether);
        depository.initialize(msg.sender, bridge, msg.sender, bytes32(abi.encode(1)));
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

    function testRevertOnlyStakedAvail_mint(address account, uint256 amount) external {
        vm.expectRevert(IAvailWithdrawalHelper.OnlyStakedAvail.selector);
        withdrawalHelper.mint(account, amount);
    }

    function testRevertInvalidWithdrawalAmount_mint(address account, uint256 amount) external {
        vm.assume(amount < withdrawalHelper.minWithdrawal());
        vm.prank(address(stakedAvail));
        vm.expectRevert(IAvailWithdrawalHelper.InvalidWithdrawalAmount.selector);
        withdrawalHelper.mint(account, amount);
    }

    function test_mint(address account, uint256 amount) external {
        vm.assume(amount > withdrawalHelper.minWithdrawal() && account != address(0));
        vm.prank(address(stakedAvail));
        withdrawalHelper.mint(account, amount);
        assertEq(withdrawalHelper.withdrawalAmount(), amount);
        assertEq(withdrawalHelper.lastTokenId(), 1);
        assertEq(withdrawalHelper.withdrawalAmounts(1), amount);
        assertEq(withdrawalHelper.previewFulfill(1), amount);
    }

    function test_mintTwice(address account, uint248 amount) external {
        vm.assume(amount > withdrawalHelper.minWithdrawal() && account != address(0));
        vm.startPrank(address(stakedAvail));
        withdrawalHelper.mint(account, amount);
        withdrawalHelper.mint(account, amount);
        assertEq(withdrawalHelper.withdrawalAmount(), uint256(amount) * 2);
        assertEq(withdrawalHelper.lastTokenId(), 2);
        assertEq(withdrawalHelper.withdrawalAmounts(1), amount);
        assertEq(withdrawalHelper.withdrawalAmounts(2), amount);
        assertEq(withdrawalHelper.previewFulfill(2), uint256(amount) * 2);
    }

    function testRevertNotFulfilled_burn(address account, uint256 amount) external {
        vm.assume(amount > withdrawalHelper.minWithdrawal() && account != address(0));
        vm.prank(address(stakedAvail));
        withdrawalHelper.mint(account, amount);
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
        withdrawalHelper.burn(1);
        assertEq(withdrawalHelper.withdrawalAmount(), 0);
        assertEq(withdrawalHelper.lastFulfillment(), 1);
        assertEq(withdrawalHelper.previewFulfill(1), 0);
        assertEq(withdrawalHelper.withdrawalAmounts(1), 0);
        assertEq(avail.balanceOf(from), amount);
    }

    function test_burnTwice(uint248 amount) external {
        vm.assume(amount > withdrawalHelper.minWithdrawal());
        address from = makeAddr("from");
        avail.mint(from, amount);
        vm.startPrank(from);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        stakedAvail.burn(amount);
        avail.mint(address(withdrawalHelper), amount);
        withdrawalHelper.burn(1);
        assertEq(withdrawalHelper.withdrawalAmount(), 0);
        assertEq(withdrawalHelper.lastFulfillment(), 1);
        assertEq(withdrawalHelper.previewFulfill(1), 0);
        assertEq(withdrawalHelper.withdrawalAmounts(1), 0);
        assertEq(avail.balanceOf(from), amount);
    }
}
