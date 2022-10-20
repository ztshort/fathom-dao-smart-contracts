// SPDX-License-Identifier: AGPL 3.0
// Copyright Fathom 2022

pragma solidity ^0.8.13;

interface IXDCStakingStorage {

    function totalStreamShares() external view returns (uint256);


    function totalAmountOfStakedXDC() external view returns (uint256);

    function totalPenaltyBalance() external view returns (uint256);
}
