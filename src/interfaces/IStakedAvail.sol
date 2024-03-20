// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IStakedAvail is IERC20Permit {
    function updateAssets(uint256 _assets) external;
    function forceUpdateAssets(uint256 _assets) external;
    function updateDepository(address _depository) external;
    function updateWithdrawalHelper(address _withdrawalHelper) external;
    function previewMint(uint256 amount) external view returns (uint256);
    function previewBurn(uint256 amount) external view returns (uint256);
    function mintWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    function mint(uint256 amount) external;
    function mintTo(address to, uint256 amount) external;
    function burn(uint256 amount) external;
}
