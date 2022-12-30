// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract DaoToken is ERC20Votes {
    uint8 private constant DECIMALS = 6;
    uint256 private constant INITIAL_SUPPLY = 100;

    constructor() ERC20("DAOTOK", "DAO") ERC20Permit("DAOTOK") {
        _mint(msg.sender, INITIAL_SUPPLY * 10 ** DECIMALS);
    }

    function decimals() public view virtual override returns (uint8) {
        return DECIMALS;
    }
}
