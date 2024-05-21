// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.26;

import {IAvailBridge} from "./IAvailBridge.sol";

interface IAvailDepository {
    error OnlyDepositor();
    error ZeroAddress();

    event Deposit(uint256 amount);

    function updateDepository(bytes32 _depository) external;
    function deposit() external;
}
