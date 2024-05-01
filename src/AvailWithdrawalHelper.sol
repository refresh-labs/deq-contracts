// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStakedAvail} from "src/interfaces/IStakedAvail.sol";
import {
    IERC165,
    IERC721,
    IERC721Metadata,
    ERC721Upgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {IAvailWithdrawalHelper} from "src/interfaces/IAvailWithdrawalHelper.sol";
import {Ownable2StepUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

contract AvailWithdrawalHelper is ERC721Upgradeable, Ownable2StepUpgradeable, IAvailWithdrawalHelper {
    using SafeERC20 for IERC20;

    IERC20 public immutable avail;
    IStakedAvail public stAvail;
    uint256 public lastTokenId;
    uint256 public withdrawalAmount;
    uint256 public lastFulfillment;
    uint256 public minWithdrawal;
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

    function previewFulfill(uint256 till) public view returns (uint256) {
        uint256 amount = 0; // @audit-info: No need to initialize amount to 0
        uint256 i = lastFulfillment + 1;
        for (; i <= till;) {
            amount += withdrawals[i].amount;
            unchecked {
                ++i;
            }
        }
        return amount;
    }

    function mint(address account, uint256 amount, uint256 shares) external {
        if (msg.sender != address(stAvail)) revert OnlyStakedAvail();
        if (amount < minWithdrawal) revert InvalidWithdrawalAmount();
        uint256 tokenId;
        unchecked {
            tokenId = ++lastTokenId;
        }

        withdrawals[tokenId] = Withdrawal(amount, shares);
        // slither-disable-next-line events-maths
        withdrawalAmount += amount;
        _mint(account, tokenId);
    }

    function burn(uint256 id) external {
        if (lastFulfillment < id) {
            // increment lastFulfillment to id
            _fulfill(id);
        }
        Withdrawal memory withdrawal = withdrawals[id];
        address owner = ownerOf(id);
        withdrawalAmount -= withdrawal.amount;
        delete withdrawals[id];
        _burn(id);
        stAvail.updateAssetsFromWithdrawals(withdrawal.amount, withdrawal.shares);
        avail.safeTransfer(owner, withdrawal.amount);
    }

    function getWithdrawal(uint256 id) external view returns (uint256 amount, uint256 shares) {
        Withdrawal memory withdrawal = withdrawals[id];
        return (withdrawal.amount, withdrawal.shares);
    }   

    function _fulfill(uint256 till) private {
        if (avail.balanceOf(address(this)) < previewFulfill(till)) {
            revert NotFulfilled();
        }
        lastFulfillment = till;
    }
}
