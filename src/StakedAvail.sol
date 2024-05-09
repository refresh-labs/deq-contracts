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
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignedMath} from "lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol";

import {IStakedAvail} from "src/interfaces/IStakedAvail.sol";
import {IAvailWithdrawalHelper} from "src/interfaces/IAvailWithdrawalHelper.sol";

/// @title StakedAvail
/// @author Deq Protocol
/// @notice Contract for staking Avail ERC20 tokens and minting an equivalent LST
contract StakedAvail is PausableUpgradeable, ERC20PermitUpgradeable, AccessControlDefaultAdminRulesUpgradeable, IStakedAvail {
    using Math for uint256;
    using SignedMath for int256;
    using SafeERC20 for IERC20;

    bytes32 private constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 private constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    /// @notice Address of Avail ERC20 token
    IERC20 public immutable avail;
    /// @notice Address of the depository contract that bridges assets to Avail
    address public depository;
    /// @notice Address of the contract that facilitates withdrawals
    IAvailWithdrawalHelper public withdrawalHelper;
    /// @notice Amount of assets staked (in wei)
    uint256 public assets;

    /// @notice Constructor for the StakedAvail contract
    /// @param newAvail Address of the Avail ERC20 token
    constructor(IERC20 newAvail) {
        if (address(newAvail) == address(0)) revert ZeroAddress();
        avail = newAvail;
    }

    /// @notice Initializes the StakedAvail contract with governance, updater, depository, and withdrawal helper
    /// @param governance Address of the governance role
    /// @param updater Address of the updater role
    /// @param newDepository Address of the depository contract
    /// @param newWithdrawalHelper Minimum withdrawal amount required for an exit through protocol
    function initialize(
        address governance,
        address pauser,
        address updater,
        address newDepository,
        IAvailWithdrawalHelper newWithdrawalHelper
    ) external initializer {
        if (
            governance == address(0) || updater == address(0) || newDepository == address(0)
                || address(newWithdrawalHelper) == address(0)
        ) {
            revert ZeroAddress();
        }
        depository = newDepository;
        withdrawalHelper = newWithdrawalHelper;
        __ERC20_init("Staked Avail", "stAVAIL");
        __ERC20Permit_init("Staked Avail");
        __AccessControlDefaultAdminRules_init(0, governance);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(UPDATER_ROLE, updater);
    }

    /**
     * @notice  Updates pause status of the token
     * @param   status  New pause status
     */
    function setPaused(bool status) external onlyRole(PAUSER_ROLE) {
        if (status) {
            _pause();
        } else {
            _unpause();
        }
    }

    /// @notice Allows updater role to update assets based on staking rewards
    /// @dev Negative delta decreases assets, positive delta increases assets
    /// @param delta Amount to update assets by
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

    /// @notice Allows withdrawal helper to update assets and supply based on withdrawals
    /// @dev Decreases assets and supply based on amount and shares stored at time of exit
    /// @param amount Amount of Avail withdrawn
    /// @param shares Amount of staked Avail burned
    function updateAssetsFromWithdrawals(uint256 amount, uint256 shares) external {
        if (msg.sender != address(withdrawalHelper)) revert OnlyWithdrawalHelper();
        uint256 _assets = assets - amount;
        assets = _assets;
        _burn(address(this), shares);

        emit AssetsUpdated(_assets);
    }

    /// @notice Allows governance to force update assets in case of incidents
    /// @dev Reverts if newAssets is 0
    /// @param newAssets New amount of assets
    function forceUpdateAssets(uint256 newAssets) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAssets == 0) revert InvalidUpdate();
        assets = newAssets;

        emit AssetsUpdated(newAssets);
    }

    /// @notice Allows governance to update the depository address
    /// @dev Reverts if newDepository is the zero address
    /// @param newDepository Address of the new depository contract
    function updateDepository(address newDepository) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDepository == address(0)) revert ZeroAddress();
        depository = newDepository;

        emit DepositoryUpdated(newDepository);
    }

    /// @notice Allows governance to update the withdrawal helper contract
    /// @dev Reverts if newWithdrawalHelper is the zero address
    /// @param newWithdrawalHelper Address of the new withdrawal helper contract
    function updateWithdrawalHelper(IAvailWithdrawalHelper newWithdrawalHelper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(newWithdrawalHelper) == address(0)) revert ZeroAddress();
        withdrawalHelper = newWithdrawalHelper;

        emit WithdrawalHelperUpdated(address(newWithdrawalHelper));
    }

    /// @notice Returns the amount of LST to mint based on the amount of Avail staked
    /// @dev Rounds down to the nearest integer
    function previewMint(uint256 amount) public view returns (uint256 shares) {
        return amount.mulDiv(totalSupply() + 1, assets + 1, Math.Rounding.Floor);
    }

    /// @notice Returns the amount of Avail to withdraw based on the amount of LST burned
    /// @dev Rounds down to the nearest integer
    function previewBurn(uint256 shares) public view returns (uint256 amount) {
        return shares.mulDiv(assets + 1, totalSupply() + 1, Math.Rounding.Floor);
    }

    /// @notice Mints LST based on the amount of Avail staked with permit
    /// @dev Reverts if amount is 0
    /// @param amount Amount of Avail to stake
    /// @param deadline Deadline for the permit
    /// @param v Signature v
    /// @param r Signature r
    /// @param s Signature s
    function mintWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        uint256 shares = previewMint(amount);
        // slither-disable-next-line events-maths
        assets += amount;
        _mint(msg.sender, shares);
        try IERC20Permit(address(avail)).permit(msg.sender, address(this), amount, deadline, v, r, s) {} catch {}
        avail.safeTransferFrom(msg.sender, depository, amount);
    }

    /// @notice Mints LST based on the amount of Avail staked
    /// @dev Reverts if amount is 0
    /// @param amount Amount of Avail to stake
    function mint(uint256 amount) external whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        uint256 shares = previewMint(amount);
        // slither-disable-next-line events-maths
        assets += amount;
        _mint(msg.sender, shares);
        avail.safeTransferFrom(msg.sender, depository, amount);
    }

    /// @notice Mints LST to a recipient address based on the amount of Avail staked
    /// @dev Reverts if amount is 0
    /// @param to Address of the recipient
    /// @param amount Amount of Avail to stake
    function mintTo(address to, uint256 amount) external whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        uint256 shares = previewMint(amount);
        // slither-disable-next-line events-maths
        assets += amount;
        _mint(to, shares);
        avail.safeTransferFrom(msg.sender, depository, amount);
    }

    /// @notice Burns LST based on the amount of Avail withdrawn
    /// @dev Reverts if shares is 0
    /// @param shares Amount of LST to burn
    function burn(uint256 shares) external whenNotPaused {
        if (shares == 0) revert ZeroAmount();
        uint256 amount = previewBurn(shares);
        _transfer(msg.sender, address(this), shares);
        withdrawalHelper.mint(msg.sender, amount, shares);
    }
}
