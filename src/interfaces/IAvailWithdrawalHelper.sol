// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.26;

import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IStakedAvail} from "./IStakedAvail.sol";

interface IAvailWithdrawalHelper is IERC721 {
    struct Withdrawal {
        uint256 accAmount;
        uint256 shares;
    }

    error InvalidFulfillment();
    error InvalidInput();
    error InvalidWithdrawalAmount();
    error NotFulfilled();
    error OnlyStakedAvail();
    error ZeroAddress();

    function stAvail() external view returns (IStakedAvail);
    function lastTokenId() external view returns (uint256);
    function withdrawalAmount() external view returns (uint256);
    function lastFulfillment() external view returns (uint256);
    function minWithdrawal() external view returns (uint256);
    function previewFulfill(uint256 till) external view returns (uint256 amount);
    function mint(address account, uint256 amount, uint256 shares) external;
    function burn(uint256 id) external;
}
