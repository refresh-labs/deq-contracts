// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {IAvailWithdrawalHelper} from "./IAvailWithdrawalHelper.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IStakedAvail is IERC20 {
    error InvalidUpdate();
    error OnlyUpdater();
    error OnlyWithdrawalHelper();
    error ZeroAddress();
    error ZeroAmount();

    event AssetsUpdated(uint256 assets);
    event UpdaterUpdated(address updater);
    event DepositoryUpdated(address depository);
    event WithdrawalHelperUpdated(address withdrawalHelper);

    function updateAssets(int256 delta) external;
    function updateAssetsFromWithdrawals(uint256 amount) external;
    function forceUpdateAssets(uint256 _assets) external;
    function updateDepository(address _depository) external;
    function updateWithdrawalHelper(IAvailWithdrawalHelper _withdrawalHelper) external;
    function previewMint(uint256 amount) external view returns (uint256);
    function previewBurn(uint256 amount) external view returns (uint256);
    function mintWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    function mint(uint256 amount) external;
    function mintTo(address to, uint256 amount) external;
    function burn(uint256 amount) external;
}
