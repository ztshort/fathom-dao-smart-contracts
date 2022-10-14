// Copyright SECURRENCY INC.
// SPDX-License-Identifier: AGPL 3.0
pragma solidity ^0.8.13;

import "../StakingStructs.sol";
import "../interfaces/IStakingGetter.sol";
import "../interfaces/IStakingHandler.sol";
import "../interfaces/IStakingStorage.sol";
import "../interfaces/IStakingSetter.sol";
import "../utils/interfaces/IAdminPausable.sol";

interface IStakingGetterHelper{
    function getLatestRewardsPerShare(uint256 streamId) external view  returns (uint256);
    function getLockInfo(address account, uint256 lockId) external view  returns (LockedBalance memory);

    function getLocksLength(address account) external  view returns (uint256);

    function getLock(address account, uint lockId) external  view returns(uint128,
                                                                          uint128, 
                                                                          uint128, 
                                                                          uint128, 
                                                                          uint64,
                                                                          address);
    function getUserTotalDeposit(address account)
        external
        view
        returns (uint256);

    function getStreamClaimableAmount(uint256 streamId, address account)
        external
        view
        returns (uint256);

    function getUserTotalVotes(address account)
        external
        view
        returns (uint256);

    function getFeesForEarlyUnlock(uint256 lockId, address account) 
        external 
        view
        returns (uint256);

}