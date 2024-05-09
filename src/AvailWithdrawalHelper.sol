// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {AccessControlDefaultAdminRulesUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    IERC165,
    IERC721,
    IERC721Metadata,
    ERC721Upgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2StepUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

import {IAvailWithdrawalHelper} from "src/interfaces/IAvailWithdrawalHelper.sol";
import {IStakedAvail} from "src/interfaces/IStakedAvail.sol";

/// @title AvailWithdrawalHelper
/// @author Deq Protocol
/// @notice Contract that facilitates withdrawals from Staked Avail
/// @dev Uses the ERC721 standard to maintain withdrawal records
contract AvailWithdrawalHelper is PausableUpgradeable, AccessControlDefaultAdminRulesUpgradeable, ERC721Upgradeable, IAvailWithdrawalHelper {
    using SafeERC20 for IERC20;

    bytes32 private constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Address of the Avail ERC20 token
    IERC20 public immutable avail;
    /// @notice Address of the Staked Avail contract
    IStakedAvail public stAvail;
    /// @notice Last token ID minted + 1
    uint256 public lastTokenId;
    /// @notice Total amount of Avail to be withdrawn
    uint256 public withdrawalAmount;
    /// @notice Last token ID fulfilled
    uint256 public lastFulfillment;
    /// @notice Minimum withdrawal amount
    uint256 public minWithdrawal;
    /// @notice Remaining amount from previous fulfillments
    uint256 public remainingFulfillment;

    mapping(uint256 => Withdrawal) private withdrawals;

    constructor(IERC20 newAvail) {
        if (address(newAvail) == address(0)) revert ZeroAddress();
        avail = newAvail;
    }

    /// @notice Initializes the AvailWithdrawalHelper contract with governance, Avail, Staked Avail, and minimum withdrawal
    /// @param governance Address of the governance role
    /// @param newStAvail Address of the Staked Avail contract
    /// @param newMinWithdrawal Minimum withdrawal amount
    function initialize(address governance, address pauser, IStakedAvail newStAvail, uint256 newMinWithdrawal) external initializer {
        if (governance == address(0) || pauser == address(0) || address(newStAvail) == address(0)) revert ZeroAddress();
        stAvail = newStAvail;
        minWithdrawal = newMinWithdrawal;
        __ERC721_init("Exited Staked Avail", "exStAvail");
        __AccessControlDefaultAdminRules_init(0, governance);
        _grantRole(PAUSER_ROLE, pauser);
    }

    /**
     * @notice  Updates pause status of the helper contract
     * @param   status  New pause status
     */
    function setPaused(bool status) external onlyRole(PAUSER_ROLE) {
        if (status) {
            _pause();
        } else {
            _unpause();
        }
    }

    /// @notice Returns true if an EIP165 interfaceId is supported
    /// @param interfaceId An EIP165 interfaceId
    /// @return bool True if the interfaceId is supported, false if not
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, ERC721Upgradeable, AccessControlDefaultAdminRulesUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Returns fulfilment amount between lastFulfillment and till
    /// @dev Reverts if till is less than or equal to lastFulfillment
    /// @param till Token ID to iterate till
    function previewFulfill(uint256 till) public view returns (uint256 amount) {
        return withdrawals[till].accAmount - withdrawals[lastFulfillment].accAmount;
    }

    /// @notice Mints a new withdrawal receipt
    /// @dev Reverts if the caller is not the Staked Avail contract
    /// @param account Address of the account to mint the withdrawal receipt to
    /// @param amount Amount of Avail to transfer at receipt burn
    /// @param shares Amount of staked Avail to burn at receipt burn
    function mint(address account, uint256 amount, uint256 shares) external whenNotPaused {
        if (msg.sender != address(stAvail)) revert OnlyStakedAvail();
        if (amount < minWithdrawal) revert InvalidWithdrawalAmount();
        uint256 tokenId;
        unchecked {
            tokenId = ++lastTokenId;
        }
        withdrawals[tokenId] = Withdrawal(withdrawals[tokenId - 1].accAmount + amount, shares);
        // slither-disable-next-line events-maths
        withdrawalAmount += amount;
        _mint(account, tokenId);
    }

    /// @notice Burns a withdrawal receipt and transfers Avail to the owner
    /// @param id Token ID of the withdrawal receipt to burn
    function burn(uint256 id) external whenNotPaused {
        uint256 prevWithdrawalAccAmt = withdrawals[id - 1].accAmount;
        Withdrawal memory withdrawal = withdrawals[id];
        uint256 amount = withdrawal.accAmount - prevWithdrawalAccAmt;
        if (lastFulfillment < id) {
            // increment lastFulfillment to id
            _fulfill(id);
        }
        remainingFulfillment -= amount;
        address owner = ownerOf(id);
        withdrawalAmount -= amount;
        _burn(id);
        stAvail.updateAssetsFromWithdrawals(amount, withdrawal.shares);
        avail.safeTransfer(owner, amount);
    }

    /// @notice Returns the withdrawal amount and shares in a particular ID
    /// @param id Token ID of the withdrawal receipt
    /// @return amount Amount of Avail to transfer at receipt burn
    /// @return shares Amount of staked Avail to burn at receipt burn
    function getWithdrawal(uint256 id) external view returns (uint256 amount, uint256 shares) {
        Withdrawal memory withdrawal = withdrawals[id];
        return (withdrawal.accAmount - withdrawals[id - 1].accAmount, withdrawal.shares);
    }

    /// @notice Fulfills the withdrawal receipts till the given token ID
    /// @param till Token ID to fulfill till
    function _fulfill(uint256 till) private {
        uint256 fulfillmentRequired = previewFulfill(till) + remainingFulfillment;
        if (avail.balanceOf(address(this)) < fulfillmentRequired) {
            revert NotFulfilled();
        }
        lastFulfillment = till;
        remainingFulfillment = fulfillmentRequired;
    }
}
