// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStakedAvail} from "src/interfaces/IStakedAvail.sol";
import {ERC721Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {IAvailDepository} from "src/interfaces/IAvailDepository.sol";
import {IAvailWithdrawalHelper} from "src/interfaces/IAvailWithdrawalHelper.sol";

contract AvailWithdrawalHelper is ERC721Upgradeable, IAvailWithdrawalHelper {
    using SafeERC20 for IERC20;

    IERC20 public avail;
    IStakedAvail public stAVAIL;
    IAvailDepository public depository;
    address public fulfiller;
    uint256 public lastTokenId;
    uint256 public withdrawalAmount;
    uint256 public lastFulfillment;
    uint256 public minWithdrawal;

    mapping(uint256 => uint256) public withdrawalAmounts;

    error InvalidWithdrawalAmount();

    function initialize(IERC20 _avail, IStakedAvail _stAVAIL, IAvailDepository _depository, uint256 _minWithdrawal, address _fulfiller) external initializer {
        avail = _avail;
        stAVAIL = _stAVAIL;
        depository = _depository;
        minWithdrawal = _minWithdrawal;
        fulfiller = _fulfiller;
        __ERC721_init("Exited Staked Avail", "EXstAVAIL");
    }

    function previewFulfill(uint256 from, uint256 till) public view returns (uint256) {
        uint256 amount = 0;
        for (uint256 i = from + 1; i <= till;) {
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
        if (id > lastFulfillment) revert NotFulfilled();
        _burn(id);
        uint256 amount = withdrawalAmounts[id];
        withdrawalAmounts[id] = 0;
        IERC20(address(stAVAIL)).safeTransfer(ownerOf(id), amount);
    }

    function processFromDepository(uint256 till) external {
        if (till <= lastFulfillment || till > lastTokenId) revert InvalidInput();
        uint256 amount = previewFulfill(lastFulfillment, till);
        withdrawalAmount -= amount;
        lastFulfillment = till;
        stAVAIL.updateAssetsFromWithdrawals(amount);
        depository.withdraw(amount);
    }

    function fulfill(uint256 till) external {
        if (msg.sender != address(fulfiller)) revert OnlyFulfiller();
        if (till <= lastFulfillment || till > lastTokenId) revert InvalidInput();
        uint256 amount = previewFulfill(lastFulfillment, till);
        withdrawalAmount -= amount;
        lastFulfillment = till;
        stAVAIL.updateAssetsFromWithdrawals(amount);
        avail.safeTransferFrom(msg.sender, address(this), amount);
    }
}
