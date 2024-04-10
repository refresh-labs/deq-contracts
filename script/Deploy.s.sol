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
        IAvailBridge bridge = IAvailBridge(vm.envAddress("BRIDGE"));
        address updater = vm.envAddress("UPDATER");
        address governance = vm.envAddress("GOVERNANCE");
        address avail = vm.envAddress("AVAIL");
        bytes32 availDepository = vm.envBytes32("DEPOSITORY");
        address depositoryImpl = address(new AvailDepository(IERC20(avail)));
        AvailDepository depository =
            AvailDepository(address(new TransparentUpgradeableProxy(depositoryImpl, admin, "")));
        address withdrawalHelperImpl = address(new AvailWithdrawalHelper(IERC20(avail)));
        AvailWithdrawalHelper withdrawalHelper =
            AvailWithdrawalHelper(address(new TransparentUpgradeableProxy(withdrawalHelperImpl, admin, "")));
        address stAVAILimpl = address(new StakedAvail(IERC20(avail)));
        StakedAvail stAVAIL = StakedAvail(address(new TransparentUpgradeableProxy(stAVAILimpl, admin, "")));
        depository.initialize(governance, bridge, updater, availDepository);
        withdrawalHelper.initialize(governance, stAVAIL, 1 ether);
        stAVAIL.initialize(governance, updater, address(depository), withdrawalHelper);
        vm.stopBroadcast();
    }
}
