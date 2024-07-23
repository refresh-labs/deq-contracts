// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IAvailBridge} from "src/interfaces/IAvailBridge.sol";
import {IERC20, StakedAvail} from "src/StakedAvail.sol";
import {DeqRouter} from "src/DeqRouter.sol";
import {IAvailWithdrawalHelper, AvailWithdrawalHelper} from "src/AvailWithdrawalHelper.sol";
import {AvailDepository} from "src/AvailDepository.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast();
        address upgrader = vm.envAddress("UPGRADER");
        IAvailBridge bridge = IAvailBridge(vm.envAddress("BRIDGE"));
        address avail = vm.envAddress("AVAIL");
        address updater = vm.envAddress("UPDATER");
        address governance = vm.envAddress("GOVERNANCE");
        address pauser = vm.envAddress("PAUSER");
        bytes32 availDepository = vm.envBytes32("DEPOSITORY");
        address swapRouter = vm.envAddress("SWAP_ROUTER");
        address depositoryImpl = address(new AvailDepository(IERC20(avail), bridge));
        AvailDepository depository =
            AvailDepository(address(new TransparentUpgradeableProxy(depositoryImpl, upgrader, "")));
        address withdrawalHelperImpl = address(new AvailWithdrawalHelper(IERC20(avail)));
        AvailWithdrawalHelper withdrawalHelper =
            AvailWithdrawalHelper(address(new TransparentUpgradeableProxy(withdrawalHelperImpl, upgrader, "")));
        address stAVAILimpl = address(new StakedAvail(IERC20(avail)));
        StakedAvail stAVAIL = StakedAvail(address(new TransparentUpgradeableProxy(stAVAILimpl, upgrader, "")));
        depository.initialize(governance, pauser, updater, availDepository);
        withdrawalHelper.initialize(governance, pauser, stAVAIL, 1 ether);
        stAVAIL.initialize(governance, pauser, updater, address(depository), withdrawalHelper);
        address deqRouterImpl = address(new DeqRouter(IERC20(avail)));
        DeqRouter deqRouter = DeqRouter(address(new TransparentUpgradeableProxy(deqRouterImpl, upgrader, "")));
        deqRouter.initialize(governance, pauser, swapRouter, StakedAvail(stAVAIL));
        vm.stopBroadcast();
        console.log("  ############################################################  ");
        console.log("Deployed AvailDepository at:", address(depository));
        console.log("Deployed AvailWithdrawalHelper at:", address(withdrawalHelper));
        console.log("Deployed StakedAvail at:", address(stAVAIL));
        console.log("Deployed DeqRouter at:", address(deqRouter));
        console.log("  ############################################################  ");
    }
}
