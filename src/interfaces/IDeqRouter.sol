// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

interface IDeqRouter {
    struct Transformation {
        uint32 _uint32;
        bytes _bytes;
    }

    error ApprovalFailed();
    error ExceedsSlippage();
    error InvalidInputAmount();
    error InvalidInputToken();
    error InvalidOutputToken();
    error SwapFailed(string msg);
    error ZeroAddress();

    function swapERC20ToStAvail(address allowanceTarget, bytes calldata data) external;

    function swapERC20ToStAvailWithPermit(
        address allowanceTarget,
        bytes calldata data,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function swapETHtoStAvail(bytes calldata data) external payable;
}
