// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {ERC20Upgradeable, ERC20PermitUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

contract StakedAvail is Initializable, ERC20PermitUpgradeable, Ownable2StepUpgradeable  {
    using SafeERC20 for IERC20;

    /// @notice Address of Avail ERC20 token
    IERC20 constant avail = IERC20(address(0)); // TODO: update when available!
    /// @notice Address of the depository contract that bridges assets to Avail
    address public depository;
    /// @notice Address of the contract that facilitates withdrawals
    address public withdrawalHelper;
    /// @notice Amount of assets staked (in wei)
    uint256 public assets;
    /// @notice Address of updater contract
    address public updater;

    error OnlyUpdater();
    error ZeroAddress();
    error ZeroAmount();

    event AssetsUpdated(uint256 assets);
    event DepositoryUpdated(address depository);
    event WithdrawalHelperUpdated(address withdrawalHelper);

    function initialize(address governance, address _updater, address _depository, address _withdrawalHelper) external initializer {
        __ERC20_init("Staked Avail", "stAVAIL");
        __ERC20Permit_init("Staked Avail");
        _transferOwnership(governance);
        updater = _updater;
        depository =  _depository;
        withdrawalHelper = _withdrawalHelper;
    }

    function updateAssets(uint256 _assets) external {
        if (msg.sender != updater) revert OnlyUpdater();
        assets = _assets;

        emit AssetsUpdated(_assets);
    }

    function forceUpdateAssets(uint256 _assets) external onlyOwner {
        assets = _assets;

        emit AssetsUpdated(_assets);
    }

    function updateDepository(address _depository) external onlyOwner {
        if (_depository == address(0)) revert ZeroAddress();
        depository = _depository;

        emit DepositoryUpdated(_depository);
    }

    function updateWithdrawalHelper(address _withdrawalHelper) external onlyOwner {
        if (_withdrawalHelper == address(0)) revert ZeroAddress();
        withdrawalHelper = _withdrawalHelper;

        emit WithdrawalHelperUpdated(_withdrawalHelper);
    }

    function mintWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        IERC20Permit(address(avail)).permit(msg.sender, address(this), amount, deadline, v, r, s);
        avail.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }

    function mint(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        avail.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _burn(msg.sender, amount);
    }
}
