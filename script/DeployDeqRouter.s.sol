// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import {IERC20, StakedAvail} from "src/StakedAvail.sol";
import {DeqRouter} from "src/DeqRouter.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract DeployDeqRouterScript is Script {
    function run() external {
        vm.startBroadcast();

        address swapRouter = vm.envAddress("SWAP_ROUTER");
        address avail = vm.envAddress("AVAIL");
        address stAVAIL = vm.envAddress("ST_AVAIL");
        DeqRouter deqRouter = new DeqRouter(swapRouter, IERC20(avail), StakedAvail(stAVAIL));
        vm.stopBroadcast();
        console.log("  ############################################################  ");
        console.log("Deployed DeqRouter at:", address(deqRouter));
        console.log("  ############################################################  ");
    }
}
