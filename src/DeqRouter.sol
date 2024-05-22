// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.26;

import {AccessControlDefaultAdminRulesUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IDeqRouter} from "src/interfaces/IDeqRouter.sol";
import {IStakedAvail} from "src/interfaces/IStakedAvail.sol";

/// @title DeqRouter
/// @author Deq Protocol
/// @notice Router contract for swapping ERC20 tokens to Avail and minting staked Avail
/// @dev The contract is upgradeable. The router does not support fee-on-transfer tokens as 0x proxy does not.
contract DeqRouter is PausableUpgradeable, AccessControlDefaultAdminRulesUpgradeable, IDeqRouter {
    using SafeERC20 for IERC20;

    bytes32 private constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Address of the Avail ERC20 token
    IERC20 public immutable avail;
    /// @notice Address of the 0x proxy swap router contract
    address public swapRouter;
    /// @notice Address of the staked Avail contract
    IStakedAvail public stAvail;

    constructor(IERC20 newAvail) {
        require(address(newAvail) != address(0), ZeroAddress());
        avail = newAvail;
        _disableInitializers();
    }

    /// @notice Initialization funciton for the DeqRouter contract
    /// @param governance Address of the governance role
    /// @param pauser Address of the pauser role
    /// @param newSwapRouter Address of the 0x proxy swap router contract
    /// @param newStAvail Address of the staked Avail contract
    function initialize(address governance, address pauser, address newSwapRouter, IStakedAvail newStAvail)
        external
        initializer
    {
        require(
            governance != address(0) && pauser != address(0) && newSwapRouter != address(0)
                && address(newStAvail) != address(0),
            ZeroAddress()
        );
        swapRouter = newSwapRouter;
        stAvail = newStAvail;
        __AccessControlDefaultAdminRules_init(0, governance);
        _grantRole(PAUSER_ROLE, pauser);
    }

    /// @notice Updates pause status of the depository
    /// @dev Setting true pauses the contract, setting false unpauses the contract
    /// @param status New pause status
    function setPaused(bool status) external onlyRole(PAUSER_ROLE) {
        if (status) {
            _pause();
        } else {
            _unpause();
        }
    }

    /// @notice Updates the swap router address
    /// @param newSwapRouter Address of the new swap router
    function updateSwapRouter(address newSwapRouter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newSwapRouter != address(0), ZeroAddress());
        swapRouter = newSwapRouter;
    }

    /// @notice Swaps an ERC20 token to staked Avail
    /// @param allowanceTarget Address of the allowance target from 0x API
    /// @param deadline Deadline for the swap
    /// @param data Data for the swap from 0x API
    function swapERC20ToStAvail(address allowanceTarget, uint256 deadline, bytes calldata data)
        external
        whenNotPaused
    {
        // slither-disable-next-line timestamp
        require(block.timestamp <= deadline, ExpiredDeadline());
        (IERC20 tokenIn, IERC20 tokenOut, uint256 inAmount, uint256 minOutAmount,) =
            abi.decode(data[4:], (IERC20, IERC20, uint256, uint256, Transformation[]));
        require(address(tokenOut) == address(avail), InvalidOutputToken());
        tokenIn.safeTransferFrom(msg.sender, address(this), inAmount);
        tokenIn.forceApprove(allowanceTarget, inAmount);
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory result) = swapRouter.call(data);
        require(success, SwapFailed(string(result)));
        uint256 outAmount = abi.decode(result, (uint256));
        require(outAmount >= minOutAmount, ExceedsSlippage());
        // slither-disable-next-line unused-return
        avail.approve(address(stAvail), outAmount);
        stAvail.mintTo(msg.sender, outAmount);
    }

    /// @notice Swaps an ERC20 token to staked Avail with permit
    /// @param allowanceTarget Address of the allowance target from 0x API
    /// @param data Data for the swap from 0x API
    /// @param deadline Deadline for swap and permit execution
    /// @param v Signature v
    /// @param r Signature r
    /// @param s Signature s
    function swapERC20ToStAvailWithPermit(
        address allowanceTarget,
        bytes calldata data,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused {
        // slither-disable-next-line timestamp
        require(block.timestamp <= deadline, ExpiredDeadline());
        (IERC20 tokenIn, IERC20 tokenOut, uint256 inAmount, uint256 minOutAmount,) =
            abi.decode(data[4:], (IERC20, IERC20, uint256, uint256, Transformation[]));
        require(address(tokenOut) == address(avail), InvalidOutputToken());
        // if permit fails, assume executed
        try IERC20Permit(address(tokenIn)).permit(msg.sender, address(this), inAmount, deadline, v, r, s) {} catch {}
        tokenIn.safeTransferFrom(msg.sender, address(this), inAmount);
        tokenIn.forceApprove(allowanceTarget, inAmount);
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory result) = swapRouter.call(data);
        require(success, SwapFailed(string(result)));
        uint256 outAmount = abi.decode(result, (uint256));
        require(outAmount >= minOutAmount, ExceedsSlippage());
        // slither-disable-next-line unused-return
        avail.approve(address(stAvail), outAmount);
        stAvail.mintTo(msg.sender, outAmount);
    }

    /// @notice Swaps ETH to staked Avail
    /// @param deadline Deadline for the swap
    /// @param data Data for the swap from 0x API
    function swapETHtoStAvail(uint256 deadline, bytes calldata data) external payable whenNotPaused {
        // slither-disable-next-line timestamp
        require(block.timestamp <= deadline, ExpiredDeadline());
        (address tokenIn, IERC20 tokenOut, uint256 inAmount, uint256 minOutAmount,) =
            abi.decode(data[4:], (address, IERC20, uint256, uint256, Transformation[]));
        require(address(tokenIn) == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, InvalidInputToken());
        require(address(tokenOut) == address(avail), InvalidOutputToken());
        require(msg.value == inAmount, InvalidInputAmount());
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory result) = swapRouter.call{value: msg.value}(data);
        require(success, SwapFailed(string(result)));
        uint256 outAmount = abi.decode(result, (uint256));
        require(outAmount >= minOutAmount, ExceedsSlippage());
        // slither-disable-next-line unused-return
        avail.approve(address(stAvail), outAmount);
        stAvail.mintTo(msg.sender, outAmount);
    }
}
