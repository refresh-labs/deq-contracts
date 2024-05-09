// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IERC20, StakedAvail} from "src/StakedAvail.sol";
import {DeqRouter} from "src/DeqRouter.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract DeployDeqRouterScript is Script {
    function run() external {
        vm.startBroadcast();

        address governance = vm.envAddress("GOVERNANCE");
        address pauser = vm.envAddress("PAUSER");
        address swapRouter = vm.envAddress("SWAP_ROUTER");
        address avail = vm.envAddress("AVAIL");
        address stAVAIL = vm.envAddress("ST_AVAIL");
        address deqRouterImpl = address(new DeqRouter(IERC20(avail)));
        DeqRouter deqRouter = DeqRouter(address(new TransparentUpgradeableProxy(deqRouterImpl, msg.sender, "")));
        deqRouter.initialize(governance, pauser, swapRouter, StakedAvail(stAVAIL));
        vm.stopBroadcast();
        console.log("  ############################################################  ");
        console.log("Deployed DeqRouter at:", address(deqRouter));
        console.log("  ############################################################  ");
    }
}
