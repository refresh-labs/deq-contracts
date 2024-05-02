// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IDeqRouter} from "src/interfaces/IDeqRouter.sol";
import {IStakedAvail} from "src/interfaces/IStakedAvail.sol";

contract DeqRouter is IDeqRouter {
    using SafeERC20 for IERC20;

    address public immutable swapRouter;
    IERC20 public immutable avail;
    IStakedAvail public immutable stAvail;

    constructor(address newSwapRouter, IERC20 newAvail, IStakedAvail newStAvail) {
        if (newSwapRouter == address(0) || address(newAvail) == address(0) || address(newStAvail) == address(0)) {
            revert ZeroAddress();
        }
        swapRouter = newSwapRouter;
        avail = newAvail;
        stAvail = newStAvail;
    }

    function swapERC20ToStAvail(address allowanceTarget, bytes calldata data) external {
        (IERC20 tokenIn, IERC20 tokenOut, uint256 inAmount, uint256 minOutAmount,) =
            abi.decode(data[4:], (IERC20, IERC20, uint256, uint256, Transformation[]));
        if (address(tokenOut) != address(avail)) revert InvalidOutputToken();
        tokenIn.safeTransferFrom(msg.sender, address(this), inAmount);
        tokenIn.forceApprove(allowanceTarget, inAmount);
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory result) = swapRouter.call(data);
        if (!success) revert SwapFailed(string(result));
        uint256 outAmount = abi.decode(result, (uint256));
        if (outAmount < minOutAmount) revert ExceedsSlippage();
        // slither-disable-next-line unused-return
        avail.approve(address(stAvail), outAmount);
        stAvail.mintTo(msg.sender, outAmount);
    }

    function swapERC20ToStAvailWithPermit(
        address allowanceTarget,
        bytes calldata data,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        (IERC20 tokenIn, IERC20 tokenOut, uint256 inAmount, uint256 minOutAmount,) =
            abi.decode(data[4:], (IERC20, IERC20, uint256, uint256, Transformation[]));
        if (address(tokenOut) != address(avail)) revert InvalidOutputToken();
        // if permit fails, assume executed
        try IERC20Permit(address(tokenIn)).permit(msg.sender, address(this), inAmount, deadline, v, r, s) {} catch {}
        tokenIn.safeTransferFrom(msg.sender, address(this), inAmount);
        tokenIn.forceApprove(allowanceTarget, inAmount);
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory result) = swapRouter.call(data);
        if (!success) revert SwapFailed(string(result));
        uint256 outAmount = abi.decode(result, (uint256));
        if (outAmount < minOutAmount) revert ExceedsSlippage();
        // slither-disable-next-line unused-return
        avail.approve(address(stAvail), outAmount);
        stAvail.mintTo(msg.sender, outAmount);
    }

    function swapETHtoStAvail(bytes calldata data) external payable {
        (address tokenIn, IERC20 tokenOut, uint256 inAmount, uint256 minOutAmount,) =
            abi.decode(data[4:], (address, IERC20, uint256, uint256, Transformation[]));
        if (address(tokenIn) != 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) revert InvalidInputToken();
        if (address(tokenOut) != address(avail)) revert InvalidOutputToken();
        if (msg.value != inAmount) revert InvalidInputAmount();
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory result) = swapRouter.call{value: msg.value}(data);
        if (!success) revert SwapFailed(string(result));
        uint256 outAmount = abi.decode(result, (uint256));
        if (outAmount < minOutAmount) revert ExceedsSlippage();
        // slither-disable-next-line unused-return
        avail.approve(address(stAvail), outAmount);
        stAvail.mintTo(msg.sender, outAmount);
    }
}
