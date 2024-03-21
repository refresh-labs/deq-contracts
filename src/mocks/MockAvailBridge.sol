// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

contract MockAvailBridge {
    event MessageSent(bytes32 indexed account, uint256 amount);

    function sendAVAIL(bytes32 account, uint256 amount) external {
        emit MessageSent(account, amount);
    }
}
