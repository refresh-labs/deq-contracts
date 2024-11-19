// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.25;

interface INttToken {
    // NOTE: the `mint` method is not present in the standard ERC20 interface.
    function mint(address account, uint256 amount) external;

    // NOTE: NttTokens in `burn` mode require the `burn` method to be present.
    //       This method is not present in the standard ERC20 interface, but is
    //       found in the `ERC20Burnable` interface.
    function burn(uint256 amount) external;
}
