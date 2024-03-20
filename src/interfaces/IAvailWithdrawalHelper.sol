// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

interface IAvailWithdrawalHelper is IERC721 {
    error InvalidInput();
    error NotFulfilled();
    error OnlyStakedAvail();
    error OnlyFulfiller();

    function stAVAIL() external view returns (IERC20);
    function lastTokenId() external view returns (uint256);
    function withdrawalAmount() external view returns (uint256);
    function lastFulfillment() external view returns (uint256);
    function minWithdrawal() external view returns (uint256);
    function balanceof(uint256 id) external view returns (uint256 amount);
    function previewFulfill(uint256 from, uint256 till) external view returns (uint256 amount);
    function mint(address account, uint256 amount) external;
    function burn(uint256 id) external;
    function fulfill(uint256 till) external;
}
