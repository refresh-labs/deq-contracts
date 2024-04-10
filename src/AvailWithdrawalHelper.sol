// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

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
import {
    IAccessControl,
    AccessControlDefaultAdminRulesUpgradeable
} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Ownable2StepUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

contract AvailWithdrawalHelper is ERC721Upgradeable, Ownable2StepUpgradeable, IAvailWithdrawalHelper {
    using SafeERC20 for IERC20;

    IERC20 public avail;
    IStakedAvail public stAVAIL;
    uint256 public lastTokenId;
    uint256 public withdrawalAmount;
    uint256 public lastFulfillment;
    uint256 public minWithdrawal;

    mapping(uint256 => uint256) public withdrawalAmounts;

    error InvalidWithdrawalAmount();

    function initialize(address governance, IERC20 _avail, IStakedAvail _stAVAIL, uint256 _minWithdrawal)
        external
        initializer
    {
        avail = _avail;
        stAVAIL = _stAVAIL;
        minWithdrawal = _minWithdrawal;
        __ERC721_init("Exited Staked Avail", "exStAVAIL");
        _transferOwnership(governance);
    }

    function supportsInterface(bytes4 interfaceId) public view override(IERC165, ERC721Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function previewFulfill(uint256 till) public view returns (uint256) {
        uint256 amount = 0;
        uint256 i = lastFulfillment + 1;
        for (i; i <= till;) {
            amount += withdrawalAmounts[i];
            unchecked {
                ++i;
            }
        }
        return amount;
    }

    function mint(address account, uint256 amount) external {
        if (msg.sender != address(stAVAIL)) revert OnlyStakedAvail();
        if (amount < minWithdrawal) revert InvalidWithdrawalAmount();
        uint256 tokenId;
        unchecked {
            tokenId = ++lastTokenId;
        }
        withdrawalAmounts[tokenId] = amount;
        withdrawalAmount += amount;
        _mint(account, tokenId);
    }

    function burn(uint256 id) external {
        if (lastFulfillment < id) {
            // increment lastFulfillment to id
            _fulfill(id);
        }
        _burn(id);
        uint256 amount = withdrawalAmounts[id];
        withdrawalAmount -= amount;
        withdrawalAmounts[id] = 0;
        stAVAIL.updateAssetsFromWithdrawals(amount);
        avail.safeTransfer(ownerOf(id), amount);
    }

    function _fulfill(uint256 till) private {
        uint256 amount = previewFulfill(till);
        if (avail.balanceOf(address(this)) < amount) {
            revert NotFulfilled();
        }
        lastFulfillment = till;
    }
}
