// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {Ownable2StepUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {IAvailBridge} from "src/interfaces/IAvailBridge.sol";
import {IAvailWithdrawalHelper} from "src/interfaces/IAvailWithdrawalHelper.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAvailDepository} from "src/interfaces/IAvailDepository.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

contract AvailDepository is AccessControlDefaultAdminRulesUpgradeable, IAvailDepository {
    using SafeERC20 for IERC20;

    bytes32 private constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    IERC20 public immutable avail;
    IAvailBridge public bridge;
    address public depositor;
    bytes32 public depository;

    constructor(IERC20 _avail) {
        if (address(_avail) == address(0)) revert ZeroAddress();
        avail = _avail;
    }

    function initialize(address governance, IAvailBridge _bridge, address _depositor, bytes32 _depository)
        external
        initializer
    {
        if (address(_bridge) == address(0) || _depositor == address(0) || _depository == bytes32(0)) {
            revert ZeroAddress();
        }
        bridge = _bridge;
        depository = _depository;
        __AccessControlDefaultAdminRules_init(0, governance);
        _grantRole(DEPOSITOR_ROLE, _depositor);
    }

    function updateBridge(IAvailBridge _bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(_bridge) == address(0)) revert ZeroAddress();
        bridge = _bridge;
    }

    function updateDepository(bytes32 _depository) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_depository == bytes32(0)) revert ZeroAddress();
        depository = _depository;
    }

    function deposit() external onlyRole(DEPOSITOR_ROLE) {
        uint256 amount = avail.balanceOf(address(this));
        if (!avail.approve(address(bridge), amount)) revert ApprovalFailed();
        bridge.sendAVAIL(depository, amount);
    }
}
