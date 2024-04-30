// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {IAvailBridge} from "src/interfaces/IAvailBridge.sol";
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
    bytes32 public depository;

    constructor(IERC20 newAvail) {
        if (address(newAvail) == address(0)) revert ZeroAddress();
        avail = newAvail;
    }

    function initialize(address governance, IAvailBridge newBridge, address newDepositor, bytes32 newDepository)
        external
        initializer
    {
        if (governance == address(0) || address(newBridge) == address(0) || newDepositor == address(0) || newDepository == bytes32(0)) {
            revert ZeroAddress();
        }
        bridge = newBridge;
        depository = newDepository;
        __AccessControlDefaultAdminRules_init(0, governance);
        _grantRole(DEPOSITOR_ROLE, newDepositor);
    }

    function updateBridge(IAvailBridge newBridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(newBridge) == address(0)) revert ZeroAddress();
        bridge = newBridge;
    }

    function updateDepository(bytes32 newDepository) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDepository == bytes32(0)) revert ZeroAddress();
        depository = newDepository;
    }

    function deposit() external onlyRole(DEPOSITOR_ROLE) {
        uint256 amount = avail.balanceOf(address(this));
        // keep 1 wei so slot stays warm
        avail.approve(address(bridge), amount - 1);
        bridge.sendAVAIL(depository, amount - 1);
    }
}
