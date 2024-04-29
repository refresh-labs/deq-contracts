// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IStakedAvail} from "./IStakedAvail.sol";

interface IAvailWithdrawalHelper is IERC721 {
    error InvalidInput();
    error InvalidWithdrawalAmount();
    error NotFulfilled();
    error OnlyFulfiller();
    error OnlyStakedAvail();
    error ZeroAddress();

    function stAVAIL() external view returns (IStakedAvail);
    function lastTokenId() external view returns (uint256);
    function withdrawalAmount() external view returns (uint256);
    function lastFulfillment() external view returns (uint256);
    function minWithdrawal() external view returns (uint256);
    function withdrawalAmounts(uint256 id) external view returns (uint256 amount);
    function previewFulfill(uint256 till) external view returns (uint256 amount);
    function mint(address account, uint256 amount) external;
    function burn(uint256 id) external;
}
