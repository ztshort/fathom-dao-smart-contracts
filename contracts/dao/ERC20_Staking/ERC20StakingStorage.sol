// SPDX-License-Identifier: AGPL 3.0
// Original Copyright Aurora
// Copyright Fathom 2022

pragma solidity ^0.8.13;

import "./ERC20StakingStructs.sol";
import "./interfaces/IERC20StakingStorage.sol";

contract ERC20StakingStorage is IERC20StakingStorage {
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
    uint256 public override totalAmountOfStakedERC20;
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
   
    address public wERC20;

    address public vault;

    mapping(address => ERC20User) internal users;
    ERC20Stream[] internal streams;
    ///Mapping (user => LockedBalance) to keep locking information for each user
    mapping(address => ERC20LockedBalance[]) internal locks;

    ///Weighting coefficient for shares and penalties
    ERC20Weight internal weight;

    uint256 public maxLockPositions;
    address public govnContract;
    bool internal earlyWithdrawalFlag;
}
