// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    IERC165,
    IERC721,
    IERC721Metadata,
    ERC721Upgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2StepUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

import {IAvailWithdrawalHelper} from "src/interfaces/IAvailWithdrawalHelper.sol";
import {IStakedAvail} from "src/interfaces/IStakedAvail.sol";

contract AvailWithdrawalHelper is ERC721Upgradeable, Ownable2StepUpgradeable, IAvailWithdrawalHelper {
    using SafeERC20 for IERC20;

    IERC20 public immutable avail;
    IStakedAvail public stAvail;
    uint256 public lastTokenId;
    uint256 public withdrawalAmount;
    uint256 public lastFulfillment;
    uint256 public minWithdrawal;
    uint256 public remainingFulfillment;

    mapping(uint256 => Withdrawal) private withdrawals;

    constructor(IERC20 newAvail) {
        if (address(newAvail) == address(0)) revert ZeroAddress();
        avail = newAvail;
    }

    function initialize(address governance, IStakedAvail newStAvail, uint256 newMinWithdrawal) external initializer {
        if (governance == address(0) || address(newStAvail) == address(0)) revert ZeroAddress();
        stAvail = newStAvail;
        minWithdrawal = newMinWithdrawal;
        __ERC721_init("Exited Staked Avail", "exStAvail");
        _transferOwnership(governance);
    }

    function supportsInterface(bytes4 interfaceId) public view override(IERC165, ERC721Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function previewFulfill(uint256 till) public view returns (uint256 amount) {
        return withdrawals[till].accAmount - withdrawals[lastFulfillment].accAmount;
    }

    function mint(address account, uint256 amount, uint256 shares) external {
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

    function burn(uint256 id) external {
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

    function getWithdrawal(uint256 id) external view returns (uint256 amount, uint256 shares) {
        Withdrawal memory withdrawal = withdrawals[id];
        return (withdrawal.accAmount - withdrawals[id - 1].accAmount, withdrawal.shares);
    }

    function _fulfill(uint256 till) private {
        uint256 fulfillmentRequired = previewFulfill(till) + remainingFulfillment;
        if (avail.balanceOf(address(this)) < fulfillmentRequired) {
            revert NotFulfilled();
        }
        lastFulfillment = till;
        remainingFulfillment = fulfillmentRequired;
    }
}
