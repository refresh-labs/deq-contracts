// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {StdUtils, Test} from "lib/forge-std/src/Test.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {SignedMath} from "lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {IERC20, IStakedAvail, StakedAvail} from "src/StakedAvail.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {AvailDepository} from "src/AvailDepository.sol";
import {MockAvailBridge} from "src/mocks/MockAvailBridge.sol";
import {IAvailBridge} from "src/interfaces/IAvailBridge.sol";
import {IAvailWithdrawalHelper, AvailWithdrawalHelper} from "src/AvailWithdrawalHelper.sol";
import {SigUtils} from "./helpers/SigUtils.sol";
import {console} from "lib/forge-std/src/console.sol";

contract StakedAvailTest is StdUtils, Test {
    using SignedMath for int256;

    StakedAvail public stakedAvail;
    MockERC20 public avail;
    AvailDepository public depository;
    IAvailBridge public bridge;
    AvailWithdrawalHelper public withdrawalHelper;
    address owner;
    address updater;
    address pauser;
    SigUtils sigUtils;

    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    function setUp() external {
        owner = msg.sender;
        updater = makeAddr("updater");
        pauser = makeAddr("pauser");
        avail = new MockERC20("Avail", "AVAIL");
        bridge = IAvailBridge(address(new MockAvailBridge(avail)));
        address impl = address(new StakedAvail(avail));
        stakedAvail = StakedAvail(address(new TransparentUpgradeableProxy(impl, msg.sender, "")));
        address depositoryImpl = address(new AvailDepository(avail, bridge));
        depository = AvailDepository(address(new TransparentUpgradeableProxy(depositoryImpl, msg.sender, "")));
        address withdrawalHelperImpl = address(new AvailWithdrawalHelper(avail));
        withdrawalHelper =
            AvailWithdrawalHelper(address(new TransparentUpgradeableProxy(withdrawalHelperImpl, msg.sender, "")));
        withdrawalHelper.initialize(msg.sender, pauser, stakedAvail, 1 ether);
        depository.initialize(msg.sender, pauser, msg.sender, bytes32(abi.encode(1)));
        stakedAvail.initialize(msg.sender, pauser, updater, address(depository), withdrawalHelper);
    }

    function testRevertZeroAddress_constructor() external {
        vm.expectRevert(IStakedAvail.ZeroAddress.selector);
        new StakedAvail(IERC20(address(0)));
    }

    function test_constructor(address rand) external {
        vm.assume(rand != address(0));
        StakedAvail newStakedAvail = new StakedAvail(IERC20(rand));
        assertEq(address(newStakedAvail.avail()), rand);
    }

    function testRevertZeroAddress_initialize(
        address rand,
        address newOwner,
        address newPauser,
        address newUpdater,
        address newDepository,
        address newWithdrawalHelper
    ) external {
        vm.assume(
            rand != address(0)
                && (
                    newOwner == address(0) || newPauser == address(0) || newUpdater == address(0)
                        || newDepository == address(0) || newWithdrawalHelper == address(0)
                )
        );
        StakedAvail newStakedAvail = new StakedAvail(IERC20(rand));
        assertEq(address(newStakedAvail.avail()), rand);
        vm.expectRevert(IStakedAvail.ZeroAddress.selector);
        newStakedAvail.initialize(
            newOwner, newPauser, newUpdater, newDepository, IAvailWithdrawalHelper(newWithdrawalHelper)
        );
    }

    function test_initialize() external view {
        assertEq(address(stakedAvail.avail()), address(avail));
        assertEq(stakedAvail.owner(), owner);
        assertTrue(stakedAvail.hasRole(UPDATER_ROLE, updater));
        assertEq(stakedAvail.depository(), address(depository));
        assertEq(address(stakedAvail.withdrawalHelper()), address(withdrawalHelper));
    }

    function test_setPaused() external {
        vm.startPrank(pauser);
        stakedAvail.setPaused(true);
        assertTrue(stakedAvail.paused());
        vm.expectRevert(Pausable.EnforcedPause.selector);
        stakedAvail.mint(1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        stakedAvail.mintWithPermit(1, 1, 1, bytes32(0), bytes32(0));
        vm.expectRevert(Pausable.EnforcedPause.selector);
        stakedAvail.mintTo(owner, 1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        stakedAvail.burn(1);
        stakedAvail.setPaused(false);
        assertFalse(stakedAvail.paused());
    }

    function testRevertZeroAmount_mint() external {
        vm.expectRevert(IStakedAvail.ZeroAmount.selector);
        stakedAvail.mint(0);
    }

    function test_mint(uint256 amount) external {
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

    function test_mint2(uint248 amountA, uint248 amountB) external {
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

    function test_mint3(uint248 amountA, uint248 amountB, int248 rand) external {
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
        vm.startPrank(updater);
        // inflate value of stAvail
        stakedAvail.updateAssets(int256(random));
        vm.startPrank(from);
        stakedAvail.mint(amount2);
        assertLt(stakedAvail.balanceOf(from), amount1 + amount2);
        assertEq(stakedAvail.assets(), amount1 + random + amount2);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount1 + amount2);
    }

    function test_mint4(uint248 amountA, uint248 amountB) external {
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
        vm.startPrank(updater);
        uint256 reduction = amount1 / 2;
        // deflate value of stAvail
        stakedAvail.updateAssets(-int256(amount1 / 2));
        vm.startPrank(from);
        stakedAvail.mint(amount2);
        uint256 diffBalance = stakedAvail.balanceOf(from) - prevBalance;
        assertGt(diffBalance, amount2);
        assertEq(stakedAvail.assets(), amount1 + amount2 - reduction);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount1 + amount2);
    }

    function testRevertZeroAmount_mintTo(address rand) external {
        vm.expectRevert(IStakedAvail.ZeroAmount.selector);
        stakedAvail.mintTo(rand, 0);
    }

    function test_mintTo(uint256 amount) external {
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

    function testRevertZeroAmount_burn() external {
        vm.expectRevert(IStakedAvail.ZeroAmount.selector);
        stakedAvail.burn(0);
    }

    function test_burn(uint256 amount) external {
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
        (uint256 amt, uint256 shares) = withdrawalHelper.getWithdrawal(1);
        assertEq(amt, amount);
        assertEq(shares, amount);
        assertEq(withdrawalHelper.ownerOf(1), from);
        assertEq(stakedAvail.balanceOf(from), 0);
        assertEq(stakedAvail.balanceOf(address(stakedAvail)), amount);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount);
    }

    function test_burn2(uint256 amount, uint256 burnAmt) external {
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
        (uint256 amt, uint256 shares) = withdrawalHelper.getWithdrawal(1);
        assertEq(amt, burnAmt);
        assertEq(shares, burnAmt);
        assertEq(withdrawalHelper.ownerOf(1), from);
        assertEq(stakedAvail.balanceOf(from), amount - burnAmt);
        assertEq(stakedAvail.balanceOf(address(stakedAvail)), burnAmt);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount);
    }

    function test_burn3(uint128 amount, uint128 burnAmtA, uint128 burnAmtB) external {
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
        (uint256 amt, uint256 shares) = withdrawalHelper.getWithdrawal(1);
        assertEq(amt, burnAmt1);
        assertEq(shares, burnAmt1);
        assertEq(withdrawalHelper.ownerOf(1), from);
        assertEq(stakedAvail.balanceOf(from), amount - burnAmt1);
        assertEq(stakedAvail.balanceOf(address(stakedAvail)), burnAmt1);
        stakedAvail.burn(burnAmtB);
        (amt, shares) = withdrawalHelper.getWithdrawal(2);
        assertEq(amt, burnAmtB);
        assertEq(shares, burnAmtB);
        assertEq(withdrawalHelper.ownerOf(2), from);
        assertEq(stakedAvail.balanceOf(from), amount - burnAmt1 - burnAmt2);
    }

    function testRevertZeroAmount_mintWithPermit(uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        vm.expectRevert(IStakedAvail.ZeroAmount.selector);
        stakedAvail.mintWithPermit(0, deadline, v, r, s);
    }

    function test_mintWithPermit(uint256 amount, uint256 deadline) external {
        vm.assume(amount != 0 && deadline != 0);
        (address from, uint256 key) = makeAddrAndKey("from");
        vm.startPrank(from);
        avail.mint(from, amount);
        sigUtils = new SigUtils(avail.DOMAIN_SEPARATOR());
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: from,
            spender: address(stakedAvail),
            value: amount,
            nonce: avail.nonces(from),
            deadline: deadline
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);

        stakedAvail.mintWithPermit(amount, deadline, v, r, s);
        assertEq(stakedAvail.balanceOf(from), amount);
        assertEq(stakedAvail.assets(), amount);
        assertEq(avail.balanceOf(address(stakedAvail)), 0);
        assertEq(avail.balanceOf(address(depository)), amount);
    }

    function testRevertOnlyUpdater_updateAssets(int256 delta) external {
        address from = makeAddr("from");
        vm.assume(from != updater && delta != 0);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, from, UPDATER_ROLE)
        );
        vm.prank(from);
        stakedAvail.updateAssets(delta);
    }

    function testRevertInvalidUpdate_updateAssets() external {
        vm.expectRevert(IStakedAvail.InvalidUpdate.selector);
        vm.prank(updater);
        stakedAvail.updateAssets(0);
    }

    function testRevertInvalidUpdateDelta_updateAssets(int256 assets) external {
        vm.assume(assets < 0);
        vm.prank(owner);
        stakedAvail.forceUpdateAssets(assets.abs());
        vm.prank(updater);
        vm.expectRevert(IStakedAvail.InvalidUpdate.selector);
        stakedAvail.updateAssets(assets);
    }

    function test_updateAssets(uint248 assets, int240 delta) external {
        vm.assume(delta != 0 && assets != 0);
        vm.assume(uint256(assets) > uint256(int256(delta)));
        vm.prank(owner);
        stakedAvail.forceUpdateAssets(assets);
        if (delta < 0) {
            vm.startPrank(updater);
            stakedAvail.updateAssets(delta);
            assertEq(stakedAvail.assets(), uint256(assets) - uint256(int256(-delta)));
        } else {
            vm.startPrank(updater);
            stakedAvail.updateAssets(delta);
            assertEq(stakedAvail.assets(), uint256(assets) + uint256(int256(delta)));
        }
    }

    function testRevertOnlyAdmin_forceUpdateAssets(uint256 assets) external {
        address from = makeAddr("from");
        vm.assume(assets != 0 && from != owner);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, from, bytes32(0))
        );
        vm.prank(from);
        stakedAvail.forceUpdateAssets(assets);
    }

    function testRevertInvalidUpdate_forceUpdateAssets() external {
        vm.expectRevert(IStakedAvail.InvalidUpdate.selector);
        vm.prank(owner);
        stakedAvail.forceUpdateAssets(0);
    }

    function test_forceUpdateAssets(uint256 assets) external {
        vm.assume(assets != 0);
        vm.prank(owner);
        stakedAvail.forceUpdateAssets(assets);
        assertEq(stakedAvail.assets(), assets);
    }

    function testRevertOnlyAdmin_updateDepository(address newDepository) external {
        address from = makeAddr("from");
        vm.assume(from != owner);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, from, bytes32(0))
        );
        vm.prank(from);
        stakedAvail.updateDepository(newDepository);
    }

    function testRevertZeroAddress_updateDepository() external {
        vm.prank(owner);
        vm.expectRevert(IStakedAvail.ZeroAddress.selector);
        stakedAvail.updateDepository(address(0));
    }

    function test_updateDepository(address newDepository) external {
        vm.assume(newDepository != address(0));
        vm.prank(owner);
        stakedAvail.updateDepository(newDepository);
        assertEq(stakedAvail.depository(), newDepository);
    }

    function testRevertOnlyAdmin_updateWithdrawalHelper(address newWithdrawalHelper) external {
        address from = makeAddr("from");
        vm.assume(from != owner);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, from, bytes32(0))
        );
        vm.prank(from);
        stakedAvail.updateWithdrawalHelper(IAvailWithdrawalHelper(newWithdrawalHelper));
    }

    function testRevertZeroAddress_updateWithdrawalHelper() external {
        vm.prank(owner);
        vm.expectRevert(IStakedAvail.ZeroAddress.selector);
        stakedAvail.updateWithdrawalHelper(IAvailWithdrawalHelper(address(0)));
    }

    function test_updateWithdrawalHelper(address newWithdrawalHelper) external {
        vm.assume(newWithdrawalHelper != address(0));
        vm.prank(owner);
        stakedAvail.updateWithdrawalHelper(IAvailWithdrawalHelper(newWithdrawalHelper));
        assertEq(address(stakedAvail.withdrawalHelper()), newWithdrawalHelper);
    }

    function testRevertOnlyWithdrawalHelper_updateAssetsFromWithdrawalHelper(uint256 amount, uint256 shares) external {
        address from = makeAddr("from");
        vm.assume(from != address(withdrawalHelper));
        vm.expectRevert(IStakedAvail.OnlyWithdrawalHelper.selector);
        vm.prank(from);
        stakedAvail.updateAssetsFromWithdrawals(amount, shares);
    }

    function test_updateAssetsFromWithdrawalHelper(
        uint256 assets,
        uint256 amount,
        uint256 burnAmount,
        uint256 burnShares
    ) external {
        vm.assume(
            assets != 0 && amount != 0 && burnAmount != 0 && burnShares != 0 && burnAmount <= assets
                && burnShares <= amount
        );
        address from = makeAddr("from");
        vm.startPrank(from);
        avail.mint(from, amount);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        // need deal here because we don't burn and get stAVAIL at stAVAIL address
        deal(address(stakedAvail), address(stakedAvail), burnShares);
        vm.startPrank(owner);
        stakedAvail.forceUpdateAssets(assets);
        vm.startPrank(address(withdrawalHelper));
        stakedAvail.updateAssetsFromWithdrawals(burnAmount, burnShares);
        assertEq(stakedAvail.assets(), assets - burnAmount);
        assertEq(stakedAvail.totalSupply(), amount - burnShares);
    }

    function test_previewMint(uint248 amount) external {
        vm.assume(amount > 2);
        uint256 initialAmount = stakedAvail.previewMint(amount);
        assertEq(initialAmount, amount);
        address from = makeAddr("from");
        vm.startPrank(from);
        avail.mint(from, amount);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        vm.startPrank(owner);
        stakedAvail.forceUpdateAssets(uint256(amount) - 2);
        assertGt(stakedAvail.previewMint(amount), initialAmount);
        stakedAvail.forceUpdateAssets(uint256(amount) + 2);
        assertLt(stakedAvail.previewMint(amount), initialAmount);
    }

    function test_previewBurn(uint248 amount) external {
        vm.assume(amount > 2);
        uint256 initialAmount = stakedAvail.previewBurn(amount);
        assertEq(initialAmount, amount);
        address from = makeAddr("from");
        vm.startPrank(from);
        avail.mint(from, amount);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        vm.startPrank(owner);
        // use two here because floor division
        stakedAvail.forceUpdateAssets(uint256(amount) - 2);
        assertLt(stakedAvail.previewBurn(amount), initialAmount);
        stakedAvail.forceUpdateAssets(uint256(amount) + 2);
        assertGt(stakedAvail.previewBurn(amount), initialAmount);
    }

    function test_previewBurn2(uint248 amount) external {
        // test that burning does not inflate value of stakedAvail
        vm.assume(amount > 4 ether);
        uint256 initialAmount = stakedAvail.previewBurn(amount);
        assertEq(initialAmount, amount);
        address from = makeAddr("from");
        vm.startPrank(from);
        avail.mint(from, amount);
        avail.approve(address(stakedAvail), amount);
        stakedAvail.mint(amount);
        vm.startPrank(from);
        // use two here because floor division
        uint256 amt = stakedAvail.previewBurn(amount / 4);
        stakedAvail.burn(amount / 4);
        uint256 amt2 = stakedAvail.previewBurn(amount / 4);
        assertEq(amt, amt2);
    }
}
