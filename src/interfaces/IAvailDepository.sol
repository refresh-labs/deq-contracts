// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import {IAvailBridge} from "./IAvailBridge.sol";

interface IAvailDepository {
    error ZeroAddress();
    error OnlyDepositor();

    function updateBridge(IAvailBridge _bridge) external;
    function updateDepository(bytes32 _depository) external;
    function deposit() external;
}
