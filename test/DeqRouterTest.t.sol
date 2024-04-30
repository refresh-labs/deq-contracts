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
import {AvailWithdrawalHelper} from "src/AvailWithdrawalHelper.sol";
import {IDeqRouter, DeqRouter} from "src/DeqRouter.sol";
import {SigUtils} from "./helpers/SigUtils.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeqRouterTest is Test {
    StakedAvail public stakedAvail;
    MockERC20 public avail;
    AvailDepository public depository;
    IAvailBridge public bridge;
    AvailWithdrawalHelper public withdrawalHelper;
    address public owner;
    address public swapRouter;
    DeqRouter public deqRouter;
    SigUtils public sigUtils;

    function setUp() external {
        owner = msg.sender;
        avail = new MockERC20("Avail", "AVAIL");
        bridge = IAvailBridge(address(new MockAvailBridge(avail)));
        swapRouter = makeAddr("swapRouter");
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
        deqRouter = new DeqRouter(swapRouter, avail, stakedAvail);
    }

    function test_constructor() external view {
        assertEq(address(deqRouter.swapRouter()), swapRouter);
        assertEq(address(deqRouter.avail()), address(avail));
        assertEq(address(deqRouter.stAvail()), address(stakedAvail));
    }

    function testRevert_constructor(address newSwapRouter, address newAvail, address newStakedAvail) external {
        vm.assume(newSwapRouter == address(0) || newAvail == address(0) || newStakedAvail == address(0));
        vm.expectRevert(IDeqRouter.ZeroAddress.selector);
        new DeqRouter(address(0), IERC20(address(0)), IStakedAvail(address(0)));
    }

    function test_swapERC20ToStAvail(bytes4 rand, uint256 amountIn, uint256 amountOut, uint256 minAmountOut) external {
        vm.assume(amountIn > 0 && amountOut > 0 && minAmountOut > 0 && minAmountOut <= amountOut);
        MockERC20 tokenIn = new MockERC20("TokenIn", "TKNIN");
        address from = makeAddr("from");
        tokenIn.mint(from, amountIn);
        vm.startPrank(from);
        tokenIn.approve(address(deqRouter), amountIn);
        bytes memory data = abi.encodeWithSelector(
            rand, tokenIn, address(avail), amountIn, minAmountOut, new IDeqRouter.Transformation[](0)
        );
        avail.mint(address(deqRouter), amountOut);
        vm.mockCall(swapRouter, data, abi.encode(amountOut));
        deqRouter.swapERC20ToStAvail(makeAddr("rand"), data);
        assertEq(stakedAvail.balanceOf(from), amountOut);
        assertEq(avail.balanceOf(address(deqRouter)), 0);
    }

    function test_swapERC20ToStAvailWithPermit(
        bytes4 rand,
        uint256 amountIn,
        uint256 amountOut,
        uint256 minAmountOut,
        uint256 deadline
    ) external {
        vm.assume(amountIn > 0 && amountOut > 0 && minAmountOut > 0 && minAmountOut <= amountOut && deadline != 0);
        MockERC20 tokenIn = new MockERC20("TokenIn", "TKNIN");
        (address from, uint256 key) = makeAddrAndKey("from");
        tokenIn.mint(from, amountIn);
        vm.startPrank(from);
        sigUtils = new SigUtils(tokenIn.DOMAIN_SEPARATOR());
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: from,
            spender: address(deqRouter),
            value: amountIn,
            nonce: tokenIn.nonces(from),
            deadline: deadline
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        bytes memory data = abi.encodeWithSelector(
            rand, tokenIn, address(avail), amountIn, minAmountOut, new IDeqRouter.Transformation[](0)
        );
        avail.mint(address(deqRouter), amountOut);
        vm.mockCall(swapRouter, data, abi.encode(amountOut));
        deqRouter.swapERC20ToStAvailWithPermit(makeAddr("rand"), data, deadline, v, r, s);
        assertEq(stakedAvail.balanceOf(from), amountOut);
        assertEq(avail.balanceOf(address(deqRouter)), 0);
    }

    function test_swapETHToStAvail(bytes4 rand, uint256 amountIn, uint256 amountOut, uint256 minAmountOut) external {
        vm.assume(amountIn > 0 && amountOut > 0 && minAmountOut > 0 && minAmountOut <= amountOut);
        address from = makeAddr("from");
        vm.deal(from, amountIn);
        vm.startPrank(from);
        bytes memory data = abi.encodeWithSelector(
            rand,
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            address(avail),
            amountIn,
            minAmountOut,
            new IDeqRouter.Transformation[](0)
        );
        avail.mint(address(deqRouter), amountOut);
        vm.mockCall(swapRouter, amountIn, data, abi.encode(amountOut));
        deqRouter.swapETHtoStAvail{value: amountIn}(data);
        assertEq(stakedAvail.balanceOf(from), amountOut);
        assertEq(avail.balanceOf(address(deqRouter)), 0);
    }
}
