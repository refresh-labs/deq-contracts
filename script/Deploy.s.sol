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

        IAvailBridge bridge = IAvailBridge(vm.envAddress("BRIDGE"));
        address updater = vm.envAddress("UPDATER");
        address governance = vm.envAddress("GOVERNANCE");
        address pauser = vm.envAddress("PAUSER");
        address avail = vm.envAddress("AVAIL");
        bytes32 availDepository = vm.envBytes32("DEPOSITORY");
        address depositoryImpl = address(new AvailDepository(IERC20(avail), bridge));
        AvailDepository depository =
            AvailDepository(address(new TransparentUpgradeableProxy(depositoryImpl, governance, "")));
        address withdrawalHelperImpl = address(new AvailWithdrawalHelper(IERC20(avail)));
        AvailWithdrawalHelper withdrawalHelper =
            AvailWithdrawalHelper(address(new TransparentUpgradeableProxy(withdrawalHelperImpl, governance, "")));
        address stAVAILimpl = address(new StakedAvail(IERC20(avail)));
        StakedAvail stAVAIL = StakedAvail(address(new TransparentUpgradeableProxy(stAVAILimpl, governance, "")));
        depository.initialize(governance, pauser, updater, availDepository);
        withdrawalHelper.initialize(governance, pauser, stAVAIL, 1 ether);
        stAVAIL.initialize(governance, pauser, updater, address(depository), withdrawalHelper);
        vm.stopBroadcast();
        console.log("  ############################################################  ");
        console.log("Deployed AvailDepository at:", address(depository));
        console.log("Deployed AvailWithdrawalHelper at:", address(withdrawalHelper));
        console.log("Deployed StakedAvail at:", address(stAVAIL));
        console.log("  ############################################################  ");
    }
}
