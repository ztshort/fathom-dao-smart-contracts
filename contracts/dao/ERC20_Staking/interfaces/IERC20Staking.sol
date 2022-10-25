// SPDX-License-Identifier: AGPL 3.0
// Copyright Fathom 2022

pragma solidity ^0.8.13;

import "./IERC20StakingGetter.sol";
import "./IERC20StakingHandler.sol";
import "./IERC20StakingStorage.sol";
import "./IERC20StakingSetter.sol";
import "../../staking/utils/interfaces/IAdminPausable.sol";

interface IERC20Staking is IERC20StakingGetter, IERC20StakingHandler, IERC20StakingStorage, IERC20StakingSetter, IAdminPausable {}
