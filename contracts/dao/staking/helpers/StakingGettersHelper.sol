// Copyright SECURRENCY INC.
// SPDX-License-Identifier: AGPL 3.0
pragma solidity ^0.8.13;
import "../interfaces/IStakingGetter.sol";
import "./IStakingHelper.sol";
import "../StakingStructs.sol";
import "./IStakingGetterHelper.sol";
contract StakingGettersHelper  is IStakingGetterHelper{
     // solhint-disable not-rely-on-time
    address private stakingContract;
    uint256 internal constant ONE_MONTH = 2629746;
    uint256 internal constant ONE_YEAR = 31536000;
    uint256 internal constant WEEK = 604800;
    //MAX_LOCK: It is a constant. One WEEK Added as a tolerance.
    uint256 internal constant MAX_LOCK = ONE_YEAR + WEEK;
    constructor(address _stakingContract) {
        stakingContract = _stakingContract;
    }
    function getLatestRewardsPerShare(uint256 streamId) external override view  returns (uint256) {
        return IStakingHelper(stakingContract).getLatestRewardsPerShare(streamId);
    }

    function getLockInfo(address account, uint256 lockId) external override view  returns (LockedBalance memory) {

        LockedBalance[] memory locks = IStakingHelper(stakingContract).getAllLocks(account);
        require(lockId <= locks.length, "out of index");
        return locks[lockId - 1];
    }

    function getLocksLength(address account) external override view returns (uint256) {
        LockedBalance[] memory locks = IStakingHelper(stakingContract).getAllLocks(account);
        return locks.length;
    }

    function getLock(address account, uint lockId) external
                     override view returns(uint128, uint128, uint128, uint128, uint64, address){
        LockedBalance[] memory locks = IStakingHelper(stakingContract).getAllLocks(account);
        LockedBalance memory lock = locks[lockId - 1];
        require(lockId <= locks.length, "out of index");
        return(
            lock.amountOfMAINTkn,
            lock.amountOfveMAINTkn,
            lock.mainTknShares,
            lock.positionStreamShares,
            lock.end,
            lock.owner
        );
    }

  

    /// @dev gets the total user deposit
    /// @param account the user address
    /// @return user total deposit in (Main Token)
    function getUserTotalDeposit(address account)
        external
        view
        override
        returns (uint256)
    {   
        LockedBalance[] memory locks = IStakingHelper(stakingContract).getAllLocks(account);
        if(locks.length == 0){
            return 0;
        }
        uint totalDeposit = 0;
        for(uint lockId = 1;lockId<=locks.length;lockId++){
            totalDeposit += locks[lockId - 1].amountOfMAINTkn;
        }
        return totalDeposit;
    }

    /// @dev gets the total user deposit
    /// @param account the user address
    /// @return user total deposit in (Main Token)
    function getStreamClaimableAmount(uint256 streamId, address account)
        external
        view
        override
        returns (uint256)
    {   
        LockedBalance[] memory locks = IStakingHelper(stakingContract).getAllLocks(account);
        if(locks.length == 0){
            return 0;
        }
        uint totalRewards = 0;
        for(uint lockId = 1;lockId<=locks.length;lockId++){
            totalRewards += IStakingHelper(stakingContract).getStreamClaimableAmountPerLock(
                streamId,
                account,
                lockId
            );
        }
        return totalRewards;
    }

    /// @dev gets the total user deposit
    /// @param account the user address
    /// @return user total deposit in (Main Token)
    function getUserTotalVotes(address account)
        external
        view
        override
        returns (uint256)
    {   
        LockedBalance[] memory locks = IStakingHelper(stakingContract).getAllLocks(account);
        if(locks.length == 0){
            return 0;
        }
        uint totalVotes = 0;
        for(uint lockId = 1;lockId<=locks.length;lockId++){
            totalVotes += locks[lockId - 1].amountOfveMAINTkn;
        }
        return totalVotes;
    }

    function getFeesForEarlyUnlock(uint256 lockId, address account) 
        override 
        external 
        view
        returns (uint256)
    {
        LockedBalance[] memory locks = IStakingHelper(stakingContract).getAllLocks(account);
        require(lockId <= locks.length, "out of index");
        LockedBalance memory lock = locks[lockId - 1];
        require(lock.end > block.timestamp, "lock opened, no penalty");
        uint256 totalAmountOfStakedMAINTkn = IStakingHelper(stakingContract).totalAmountOfStakedMAINTkn();
        uint256 totalMAINTknShares = IStakingHelper(stakingContract).totalMAINTknShares();
        
        uint256 amount = (totalAmountOfStakedMAINTkn * lock.mainTknShares) / totalMAINTknShares;
        uint256 lockEnd = lock.end;
        uint256 weighingCoef = _weightedPenalty(lockEnd, block.timestamp);
        uint256 penalty = (weighingCoef * amount) / 100000;
        return penalty;

    }

    function _weightedPenalty(uint256 lockEnd, uint256 timestamp) internal pure returns (uint256) {
        uint256 slopeStart = lockEnd;
        uint256 remainingTime = slopeStart - timestamp;
        //why weight multiplier: Because if a person remaining time is less than 12 hours, the calculation
        //would only give minWeightPenalty, because 2900 * 12hours/4days = 0
        if (timestamp >= slopeStart) return 0;
        Weight memory weight = Weight(1024, 256, 3000, 100, 10);
        return (weight.penaltyWeightMultiplier *
            weight.minWeightPenalty +
            (weight.penaltyWeightMultiplier * (weight.maxWeightPenalty - weight.minWeightPenalty) * remainingTime) /
            MAX_LOCK);
    }
}
