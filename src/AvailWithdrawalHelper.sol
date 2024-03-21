// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC721Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {IAvailWithdrawalHelper} from "src/interfaces/IAvailWithdrawalHelper.sol";

contract AvailWithdrawalHelper is ERC721Upgradeable, IAvailWithdrawalHelper {
    using SafeERC20 for IERC20;

    IERC20 public avail;
    IERC20 public stAVAIL;
    address public fulfiller;
    uint256 public lastTokenId;
    uint256 public withdrawalAmount;
    uint256 public lastFulfillment;
    uint256 public minWithdrawal;

    mapping(uint256 => uint256) public withdrawalAmounts;

    error InvalidWithdrawalAmount();

    function initialize(IERC20 _avail, IERC20 _stAVAIL, uint256 _minWithdrawal, address _fulfiller) external initializer {
        avail = _avail;
        stAVAIL = _stAVAIL;
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
        stAVAIL.safeTransfer(ownerOf(id), amount);
    }

    function fulfill(uint256 till) external {
        if (msg.sender != address(fulfiller)) revert OnlyFulfiller();
        if (till <= lastFulfillment || till > lastTokenId) revert InvalidInput();
        uint256 amount = previewFulfill(lastFulfillment, till);
        withdrawalAmount -= amount;
        lastFulfillment = till;
        avail.safeTransferFrom(msg.sender, address(this), amount);
    }
}
