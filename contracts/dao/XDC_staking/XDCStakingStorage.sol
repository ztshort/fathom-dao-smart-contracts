// SPDX-License-Identifier: AGPL 3.0
// Original Copyright Aurora
// Copyright Fathom 2022

pragma solidity ^0.8.13;

import "./XDCStakingStructs.sol";
import "./interfaces/IXDCStakingStorage.sol";

contract XDCStakingStorage is IXDCStakingStorage {
    uint256 internal constant RPS_MULTIPLIER = 1e31;
    uint256 internal constant POINT_MULTIPLIER = 1e18;
    uint256 internal constant ONE_MONTH = 2629746;
    uint256 internal constant ONE_YEAR = 31536000;
    uint256 internal constant WEEK = 604800;
    //MAX_LOCK: It is a constant. One WEEK Added as a tolerance.
    uint256 internal constant MAX_LOCK = ONE_YEAR + WEEK;
    ///@notice Checks if the staking is initialized
    bool internal stakingInitialised;

    uint256 internal touchedAt;

    ///@notice The below three are used for autocompounding feature and weighted shares
    uint256 public override totalAmountOfStakedXDC;
    uint256 public override totalStreamShares;


    uint256 internal totalPenaltyReleased;
    uint256 public override totalPenaltyBalance;
    address internal treasury;

    //Govenance Controlled. Add setter
    uint64 public earlyWithdrawPenaltyWeight;

    /// _lockShareCoef the weight of vote tokens during shares distribution.
    /// Should be passed in proportion of 1000. ie, if you want weight of 2, have to pass 2000
    uint256 internal lockShareCoef;
    ///_lockPeriodCoef the weight that determines the amount of vote tokens to release
    uint256 internal lockPeriodCoef;
   
    address public wXDC;

    address public vault;

    mapping(address => XDCUser) internal users;
    XDCStream[] internal streams;
    ///Mapping (user => LockedBalance) to keep locking information for each user
    mapping(address => XDCLockedBalance[]) internal locks;

    ///Weighting coefficient for shares and penalties
    XDCWeight internal weight;

    uint256 public maxLockPositions;
    address public govnContract;
    bool internal earlyWithdrawalFlag;
}
