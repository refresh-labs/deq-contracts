// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

import {AccessControlDefaultAdminRulesUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAvailBridge} from "src/interfaces/IAvailBridge.sol";
import {IAvailDepository} from "src/interfaces/IAvailDepository.sol";

/// @title AvailDepository
/// @author Deq Protocol
/// @notice Depository contract that receives Avail ERC20 and bridges assets to Avail
/// @dev The contract is upgradeable and uses AccessControlDefaultAdminRulesUpgradeable
contract AvailDepository is PausableUpgradeable, AccessControlDefaultAdminRulesUpgradeable, IAvailDepository {
    using SafeERC20 for IERC20;

    bytes32 private constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 private constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    /// @notice Address of Avail ERC20 token
    /// @dev Immutable since the ERC2O token is not upgradeable
    IERC20 public immutable avail;
    /// @notice Address of the bridge contract that bridges assets to Avail
    /// @dev The bridge contract is upgradeable
    IAvailBridge public immutable bridge;
    /// @notice Address of the depository address on Avail
    /// @dev Public key of the address receiving native Avail tokens on Avail
    bytes32 public depository;

    /// @notice Constructs the AvailDepository contract with Avail token
    /// @dev Reverts if the Avail token address is the zero address
    /// @param newAvail Address of the Avail ERC20 token
    /// @param newBridge Address of the Avail bridge contract
    constructor(IERC20 newAvail, IAvailBridge newBridge) {
        if (address(newAvail) == address(0) || address(newBridge) == address(0)) revert ZeroAddress();
        avail = newAvail;
        bridge = newBridge;
    }

    /// @notice Initializes the AvailDepository contract with governance, bridge, depositor, and depository
    /// @dev Reverts if any of the parameters are the zero address
    /// @param governance Address of the governance role
    /// @param pauser Address of the pauser role
    /// @param depositor Address of the depositor role
    /// @param newDepository Address of the depository on Avail
    function initialize(address governance, address pauser, address depositor, bytes32 newDepository)
        external
        initializer
    {
        if (governance == address(0) || pauser == address(0) || depositor == address(0) || newDepository == bytes32(0))
        {
            revert ZeroAddress();
        }
        depository = newDepository;
        __AccessControlDefaultAdminRules_init(0, governance);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(DEPOSITOR_ROLE, depositor);
    }

    /**
     * @notice  Updates pause status of the depository
     * @param   status  New pause status
     */
    function setPaused(bool status) external onlyRole(PAUSER_ROLE) {
        if (status) {
            _pause();
        } else {
            _unpause();
        }
    }

    /// @notice Updates the depository address on Avail
    /// @dev Reverts if the new depository address is the zero address
    /// @param newDepository Address of the new depository on Avail
    function updateDepository(bytes32 newDepository) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newDepository == bytes32(0)) revert ZeroAddress();
        depository = newDepository;
    }

    /// @notice Deposits Avail ERC20 to the depository on Avail
    /// @dev Reverts if the sender is not the depositor
    function deposit() external whenNotPaused onlyRole(DEPOSITOR_ROLE) {
        uint256 amount = avail.balanceOf(address(this));
        // keep 1 wei so slot stays warm, intentionally leave return unused, since OZ impl does not return false
        // slither-disable-next-line unused-return
        avail.approve(address(bridge), amount - 1);
        bridge.sendAVAIL(depository, amount - 1);
    }
}
