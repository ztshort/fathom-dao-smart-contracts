// SPDX-License-Identifier: MIT
// Original Copyright OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)
// Copyright Fathom 2022

pragma solidity ^0.8.0;

import "../../governance/token/ERC20/IERC20.sol";

interface IWXDC is IERC20{
        function deposit() payable external;
        function withdraw(uint wad)  external ;
}

