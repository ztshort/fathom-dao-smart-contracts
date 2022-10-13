// SPDX-License-Identifier: AGPL 3.0
// Copyright Fathom 2022

pragma solidity ^0.8.13;

import "../XDCStakingStructs.sol";
import "./IXDCStakingGetter.sol";
import "./IXDCStakingHandler.sol";
import "./IXDCStakingStorage.sol";
import "./IXDCStakingSetter.sol";
import "../../utils/interfaces/IAdminPausable.sol";

interface IXDCStaking is IXDCStakingGetter, IXDCStakingHandler, IXDCStakingStorage, IXDCStakingSetter, IAdminPausable {}
