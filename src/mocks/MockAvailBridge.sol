// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {MockERC20} from "./MockERC20.sol";

contract MockAvailBridge {
    MockERC20 public avail;

    event MessageSent(bytes32 indexed account, uint256 amount);

    constructor(MockERC20 newAvail) {
        avail = newAvail;
    }

    function sendAVAIL(bytes32 account, uint256 amount) external {
        avail.transferFrom(msg.sender, address(this), amount);
        avail.burn(address(this), amount);
        emit MessageSent(account, amount);
    }
}
