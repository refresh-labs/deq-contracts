// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {Test} from "lib/forge-std/src/Test.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {IERC20, StakedAvail} from "src/StakedAvail.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IAvailDepository, AvailDepository} from "src/AvailDepository.sol";
import {MockAvailBridge} from "src/mocks/MockAvailBridge.sol";
import {IAvailBridge} from "src/interfaces/IAvailBridge.sol";
import {AvailWithdrawalHelper} from "src/AvailWithdrawalHelper.sol";
import {console} from "lib/forge-std/src/console.sol";

contract AvailDepositoryTest is Test {
    StakedAvail public stakedAvail;
    MockERC20 public avail;
    AvailDepository public depository;
    IAvailBridge public bridge;
    AvailWithdrawalHelper public withdrawalHelper;
    address owner;
    address pauser;
    address depositor;
    bytes32 availDepositoryAddr;

    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    function setUp() external {
        owner = msg.sender;
        pauser = makeAddr("pauser");
        avail = new MockERC20("Avail", "AVAIL");
        depositor = makeAddr("depositor");
        availDepositoryAddr = bytes32(bytes20(makeAddr("availDepository")));
        bridge = IAvailBridge(address(new MockAvailBridge(avail)));
        address impl = address(new StakedAvail(avail));
        stakedAvail = StakedAvail(address(new TransparentUpgradeableProxy(impl, msg.sender, "")));
        address depositoryImpl = address(new AvailDepository(avail, bridge));
        depository = AvailDepository(address(new TransparentUpgradeableProxy(depositoryImpl, msg.sender, "")));
        address withdrawalHelperImpl = address(new AvailWithdrawalHelper(avail));
        withdrawalHelper =
            AvailWithdrawalHelper(address(new TransparentUpgradeableProxy(withdrawalHelperImpl, msg.sender, "")));
        withdrawalHelper.initialize(msg.sender, pauser, stakedAvail, 1 ether);
        depository.initialize(msg.sender, pauser, depositor, availDepositoryAddr);
        stakedAvail.initialize(msg.sender, pauser, msg.sender, address(depository), withdrawalHelper);
    }

    function testRevert_constructor(address rand) external {
        vm.expectRevert(IAvailDepository.ZeroAddress.selector);
        new AvailDepository(IERC20(address(0)), IAvailBridge(rand));
        vm.expectRevert(IAvailDepository.ZeroAddress.selector);
        new AvailDepository(IERC20(address(rand)), IAvailBridge(address(0)));
        vm.expectRevert(IAvailDepository.ZeroAddress.selector);
        new AvailDepository(IERC20(address(0)), IAvailBridge(address(0)));
    }

    function test_constructor(address rand) external {
        vm.assume(rand != address(0));
        AvailDepository newDepository = new AvailDepository(IERC20(rand), IAvailBridge(address(rand)));
        assertEq(address(newDepository.avail()), rand);
    }

    function testRevertZeroAddress_Initialize(
        address rand,
        address newGovernance,
        address newPauser,
        address newDepositor,
        bytes32 newAvailDepositoryAddr
    ) external {
        vm.assume(
            rand != address(0)
                && (
                    newGovernance == address(0) || newPauser == address(0) || newDepositor == address(0)
                        || newAvailDepositoryAddr == bytes32(0)
                )
        );
        AvailDepository newDepository = AvailDepository(
            address(
                new TransparentUpgradeableProxy(
                    address(new AvailDepository(IERC20(rand), IAvailBridge(rand))), makeAddr("rand"), ""
                )
            )
        );
        assertEq(address(newDepository.avail()), rand);
        vm.expectRevert(IAvailDepository.ZeroAddress.selector);
        newDepository.initialize(newGovernance, newPauser, newDepositor, newAvailDepositoryAddr);
    }

    function test_initialize() external view {
        assertEq(address(depository.avail()), address(avail));
        assertEq(address(depository.bridge()), address(bridge));
        assertEq(depository.depository(), availDepositoryAddr);
        assertTrue(depository.hasRole(PAUSER_ROLE, pauser));
        assertTrue(depository.hasRole(DEPOSITOR_ROLE, depositor));
        assertEq(depository.owner(), owner);
    }

    function test_setPaused() external {
        vm.startPrank(pauser);
        depository.setPaused(true);
        assertTrue(depository.paused());
        vm.expectRevert(Pausable.EnforcedPause.selector);
        depository.deposit();
        depository.setPaused(false);
        assertFalse(depository.paused());
    }

    function testRevertOnlyRole_updateDepository(bytes32 newDepository) external {
        vm.assume(newDepository != bytes32(0));
        address from = makeAddr("from");
        vm.assume(from != owner);
        vm.prank(from);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, from, bytes32(0))
        );
        depository.updateDepository(newDepository);
    }

    function testRevertZeroAddress_updateDepository() external {
        vm.prank(owner);
        vm.expectRevert(IAvailDepository.ZeroAddress.selector);
        depository.updateDepository(bytes32(0));
    }

    function test_updateDepository(bytes32 newDepositoryAddr) external {
        vm.assume(newDepositoryAddr != bytes32(0));
        vm.prank(owner);
        vm.assume(newDepositoryAddr != availDepositoryAddr);
        depository.updateDepository(newDepositoryAddr);
        assertEq(depository.depository(), newDepositoryAddr);
    }

    function testRevertOnlyDepositor_deposit() external {
        address from = makeAddr("from");
        vm.assume(from != depositor);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, from, DEPOSITOR_ROLE)
        );
        vm.prank(from);
        depository.deposit();
    }

    function test_deposit(uint256 amount) external {
        vm.assume(amount > 1);
        avail.mint(address(depository), amount);
        vm.prank(depositor);
        depository.deposit();
        assertEq(avail.balanceOf(address(depository)), 1);
        // bridge burns the deposited amount
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
    }

    function testRevertOnlyOwner_withdraw(IERC20 token, uint256 amount) external {
        address from = makeAddr("from");
        vm.assume(from != owner);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, from, bytes32(0))
        );
        vm.prank(from);
        depository.withdraw(token, amount);
    }

    function test_withdraw(uint256 amount) external {
        IERC20 token = new MockERC20("Token", "TKN");
        deal(address(token), address(depository), amount);
        vm.prank(owner);
        depository.withdraw(token, amount);
        assertEq(token.balanceOf(owner), amount);
    }
}
