// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Ownable2StepUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {
    ERC20Upgradeable,
    ERC20PermitUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {IAvailWithdrawalHelper} from "src/interfaces/IAvailWithdrawalHelper.sol";
import {IStakedAvail} from "src/interfaces/IStakedAvail.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

contract StakedAvail is ERC20PermitUpgradeable, AccessControlDefaultAdminRulesUpgradeable, IStakedAvail {
    using Math for uint256;
    using SafeERC20 for IERC20;

    bytes32 private constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    /// @notice Address of Avail ERC20 token
    IERC20 public immutable avail;
    /// @notice Address of the depository contract that bridges assets to Avail
    address public depository;
    /// @notice Address of the contract that facilitates withdrawals
    IAvailWithdrawalHelper public withdrawalHelper;
    /// @notice Amount of assets staked (in wei)
    uint256 public assets;

    constructor(IERC20 _avail) {
        avail = _avail;
    }

    function initialize(
        address governance,
        address _updater,
        address _depository,
        IAvailWithdrawalHelper _withdrawalHelper
    ) external initializer {
        if (_updater == address(0) || _depository == address(0) || address(_withdrawalHelper) == address(0)) {
            revert ZeroAddress();
        }
        depository = _depository;
        withdrawalHelper = _withdrawalHelper;
        __ERC20_init("Staked Avail", "stAVAIL");
        __ERC20Permit_init("Staked Avail");
        __AccessControlDefaultAdminRules_init(0, governance);
        _grantRole(UPDATER_ROLE, _updater);
    }

    function updateAssets(int256 delta) external onlyRole(UPDATER_ROLE) {
        if (delta == 0) revert InvalidUpdate();
        uint256 _assets;
        if (delta < 0) {
            _assets = assets - uint256(-delta);
        } else {
            _assets = assets + uint256(delta);
        }
        assets = _assets;

        emit AssetsUpdated(_assets);
    }

    function updateAssetsFromWithdrawals(uint256 amount) external {
        if (msg.sender != address(withdrawalHelper)) revert OnlyWithdrawalHelper();
        uint256 _assets = assets - amount;
        assets = _assets;

        emit AssetsUpdated(_assets);
    }

    function forceUpdateAssets(uint256 _assets) external onlyRole(DEFAULT_ADMIN_ROLE) {
        assets = _assets;

        emit AssetsUpdated(_assets);
    }

    function updateDepository(address _depository) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_depository == address(0)) revert ZeroAddress();
        depository = _depository;

        emit DepositoryUpdated(_depository);
    }

    function updateWithdrawalHelper(IAvailWithdrawalHelper _withdrawalHelper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(_withdrawalHelper) == address(0)) revert ZeroAddress();
        withdrawalHelper = _withdrawalHelper;

        emit WithdrawalHelperUpdated(address(_withdrawalHelper));
    }

    function previewMint(uint256 amount) public view returns (uint256) {
        return amount.mulDiv(totalSupply() + 1, assets + 1, Math.Rounding.Floor);
    }

    function previewBurn(uint256 amount) public view returns (uint256) {
        return amount.mulDiv(assets + 1, totalSupply() + 1, Math.Rounding.Floor);
    }

    function mintWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        if (amount == 0) revert ZeroAmount();
        uint256 shares = previewMint(amount);
        assets += amount;
        _mint(msg.sender, shares);
        IERC20Permit(address(avail)).permit(msg.sender, address(this), amount, deadline, v, r, s);
        avail.safeTransferFrom(msg.sender, depository, amount);
    }

    function mint(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        uint256 shares = previewMint(amount);
        assets += amount;
        _mint(msg.sender, shares);
        avail.safeTransferFrom(msg.sender, depository, amount);
    }

    function mintTo(address to, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        uint256 shares = previewMint(amount);
        assets += amount;
        _mint(to, shares);
        avail.safeTransferFrom(msg.sender, depository, amount);
    }

    function burn(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        uint256 shares = previewBurn(amount);
        _burn(msg.sender, amount);
        withdrawalHelper.mint(msg.sender, shares);
    }
}
