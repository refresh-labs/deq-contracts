// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {
    ERC20Upgradeable,
    ERC20PermitUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {INttToken} from "src/interfaces/INttToken.sol";

/// @title StakedAvail
/// @author Deq Protocol
/// @title Staked Avail ERC20 token with support for Wormhole
/// @notice A Staked Avail token implementation for Wormhole-based bridges
contract StakedAvailWormhole is AccessControlDefaultAdminRulesUpgradeable, ERC20PermitUpgradeable, INttToken {
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() {
        _disableInitializers();
    }

    function initialize() external reinitializer(2) {
        __ERC20Permit_init("Staked Avail (Wormhole)");
        __ERC20_init("Staked Avail (Wormhole)", "stAVAIL");
        // We don't need to reset the owner during reinit
        // __AccessControlDefaultAdminRules_init(0, governance);
    }

    function mint(address account, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(account, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
