// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {AccessControlDefaultAdminRulesUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {
    ERC20Upgradeable,
    ERC20PermitUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignedMath} from "lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol";

import {IStakedAvail} from "src/interfaces/IStakedAvail.sol";
import {IAvailWithdrawalHelper} from "src/interfaces/IAvailWithdrawalHelper.sol";

contract StakedAvail is ERC20PermitUpgradeable, AccessControlDefaultAdminRulesUpgradeable, IStakedAvail {
    using Math for uint256;
    using SignedMath for int256;
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

    constructor(IERC20 newAvail) {
        if (address(newAvail) == address(0)) revert ZeroAddress();
        avail = newAvail;
    }

    function initialize(
        address governance,
        address newUpdater,
        address newDepository,
        IAvailWithdrawalHelper newWithdrawalHelper
    ) external initializer {
        if (
            governance == address(0) || newUpdater == address(0) || newDepository == address(0)
                || address(newWithdrawalHelper) == address(0)
        ) {
            revert ZeroAddress();
        }
        depository = newDepository;
        withdrawalHelper = newWithdrawalHelper;
        __ERC20_init("Staked Avail", "stAVAIL");
        __ERC20Permit_init("Staked Avail");
        __AccessControlDefaultAdminRules_init(0, governance);
        _grantRole(UPDATER_ROLE, newUpdater);
    }

    function updateAssets(int256 delta) external onlyRole(UPDATER_ROLE) {
        if (delta == 0) revert InvalidUpdate();
        uint256 _assets;
        if (delta < 0) {
            _assets = assets - delta.abs();
            if (_assets == 0) revert InvalidUpdate();
        } else {
            _assets = assets + uint256(delta);
        }
        assets = _assets;

        emit AssetsUpdated(_assets);
    }

    function updateAssetsFromWithdrawals(uint256 amount, uint256 shares) external {
        if (msg.sender != address(withdrawalHelper)) revert OnlyWithdrawalHelper();
        uint256 _assets = assets - amount;
        assets = _assets;
        _burn(address(this), shares);

        emit AssetsUpdated(_assets);
    }

    function forceUpdateAssets(uint256 newAssets) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAssets == 0) revert InvalidUpdate();
        assets = newAssets;

        emit AssetsUpdated(newAssets);
    }

    function updateDepository(address newDepository) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDepository == address(0)) revert ZeroAddress();
        depository = newDepository;

        emit DepositoryUpdated(newDepository);
    }

    function updateWithdrawalHelper(IAvailWithdrawalHelper newWithdrawalHelper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(newWithdrawalHelper) == address(0)) revert ZeroAddress();
        withdrawalHelper = newWithdrawalHelper;

        emit WithdrawalHelperUpdated(address(newWithdrawalHelper));
    }

    function previewMint(uint256 amount) public view returns (uint256 shares) {
        return amount.mulDiv(totalSupply() + 1, assets + 1, Math.Rounding.Floor);
    }

    function previewBurn(uint256 shares) public view returns (uint256 amount) {
        return shares.mulDiv(assets + 1, totalSupply() + 1, Math.Rounding.Floor);
    }

    function mintWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        if (amount == 0) revert ZeroAmount();
        uint256 shares = previewMint(amount);
        // slither-disable-next-line events-maths
        assets += amount;
        _mint(msg.sender, shares);
        try IERC20Permit(address(avail)).permit(msg.sender, address(this), amount, deadline, v, r, s) {} catch {}
        avail.safeTransferFrom(msg.sender, depository, amount);
    }

    function mint(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        uint256 shares = previewMint(amount);
        // slither-disable-next-line events-maths
        assets += amount;
        _mint(msg.sender, shares);
        avail.safeTransferFrom(msg.sender, depository, amount);
    }

    function mintTo(address to, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        uint256 shares = previewMint(amount);
        // slither-disable-next-line events-maths
        assets += amount;
        _mint(to, shares);
        avail.safeTransferFrom(msg.sender, depository, amount);
    }

    function burn(uint256 shares) external {
        if (shares == 0) revert ZeroAmount();
        uint256 amount = previewBurn(shares);
        _transfer(msg.sender, address(this), shares);
        withdrawalHelper.mint(msg.sender, amount, shares);
    }
}
