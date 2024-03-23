// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import {Ownable2StepUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {IAvailBridge} from "src/interfaces/IAvailBridge.sol";
import {IAvailWithdrawalHelper} from "src/interfaces/IAvailWithdrawalHelper.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAvailDepository} from "src/interfaces/IAvailDepository.sol";

contract AvailDepository is Ownable2StepUpgradeable, IAvailDepository {
    using SafeERC20 for IERC20;

    IERC20 public immutable avail;
    IAvailBridge public bridge;
    IAvailWithdrawalHelper public withdrawalHelper;
    address public depositor;
    bytes32 public depository;

    constructor(IERC20 _avail) {
        if (address(_avail) == address(0)) revert ZeroAddress();
        avail = _avail;
    }

    function initialize(
        address governance,
        IAvailBridge _bridge,
        IAvailWithdrawalHelper _withdrawalHelper,
        address _depositor,
        bytes32 _depository
    ) external initializer {
        if (address(_bridge) == address(0) || _depositor == address(0) || _depository == bytes32(0)) {
            revert ZeroAddress();
        }
        _transferOwnership(governance);
        bridge = _bridge;
        withdrawalHelper = _withdrawalHelper;
        depositor = _depositor;
        depository = _depository;
    }

    function updateBridge(IAvailBridge _bridge) external onlyOwner {
        if (address(_bridge) == address(0)) revert ZeroAddress();
        bridge = _bridge;
    }

    function updateDepositor(address _depositor) external onlyOwner {
        if (_depositor == address(0)) revert ZeroAddress();
        depositor = _depositor;
    }

    function updateDepository(bytes32 _depository) external onlyOwner {
        if (_depository == bytes32(0)) revert ZeroAddress();
        depository = _depository;
    }

    function deposit() external {
        if (msg.sender != depositor) revert OnlyDepositor();
        uint256 amount = avail.balanceOf(address(this));
        avail.approve(address(bridge), amount);
        bridge.sendAVAIL(depository, amount);
    }

    function withdraw(uint256 amount) external {
        if (msg.sender != address(withdrawalHelper)) revert OnlyWithdrawalHelper();
        avail.safeTransfer(address(withdrawalHelper), amount);
    }
}
