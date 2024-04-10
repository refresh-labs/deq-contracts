// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.25;

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IAvailBridge} from "src/interfaces/IAvailBridge.sol";
import {IERC20, StakedAvail} from "src/StakedAvail.sol";
import {DeqRouter} from "src/DeqRouter.sol";
import {IAvailWithdrawalHelper, AvailWithdrawalHelper} from "src/AvailWithdrawalHelper.sol";
import {AvailDepository} from "src/AvailDepository.sol";
import {Script} from "forge-std/Script.sol";

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast();
        address admin = vm.envAddress("ADMIN");
        address vectorx = vm.envAddress("VECTORX");
        IAvailBridge bridge = IAvailBridge(vm.envAddress("BRIDGE"));
        address updater = vm.envAddress("UPDATER");
        address governance = vm.envAddress("GOVERNANCE");
        address avail = vm.envAddress("AVAIL");
        address depository = address(new AvailDepository(IERC20(avail)));
        AvailDepository availDepository = AvailDepository(address(new TransparentUpgradeableProxy(depository, admin, "")));
        address stAVAILimpl = address(new StakedAvail(IERC20(avail)));
        StakedAvail stAVAIL = StakedAvail(address(new TransparentUpgradeableProxy(stAVAILimpl, admin, "")));
        stAVAIL.initialize(governance, updater, admin, IAvailWithdrawalHelper(address(0)));
        vm.stopBroadcast();
    }
}
