// SPDX-License-Identifier: AGPL 3.0
// Original Copyright Aurora
// Copyright Fathom 2022

pragma solidity ^0.8.13;
import "../governance/token/ERC20/IERC20.sol";
import "../governance/interfaces/IVeMainToken.sol";
import "./XDCStakingRewardsInternals.sol";
import "../staking/vault/interfaces/IVault.sol";
import "../staking/library/BoringMath.sol";
contract XDCStakingInternals is XDCStakingStorage, XDCStakingRewardsInternals {
    // solhint-disable not-rely-on-time

    /**
     * @dev internal function to initialize the staking contracts.
     */
    function _initializeStaking(
        address _wXDC,
        Weight memory _weight,
        address _vault,
        uint256 _voteShareCoef,
        uint256 _voteLockWeight,
        uint256 _maxLockPositions
    ) internal {
        require(_wXDC != address(0x00), "zero main addrr");
        require(_vault != address(0x00), "zero vault addr");

        require(_weight.maxWeightShares > _weight.minWeightShares, "invalid share wts");
        require(_weight.maxWeightPenalty > _weight.minWeightPenalty, "invalid penalty wts");
        wXDC = _wXDC;
        weight = _weight;
        vault = _vault;
        voteShareCoef = _voteShareCoef;
        voteLockWeight = _voteLockWeight;
        maxLockPositions = _maxLockPositions;
    }

    /**
     * @dev Creates a new lock position for an account and stakes the position for rewards
     * @notice lockId is index + 1 of array of Locked Balance
     * @param account The address of the lock creator
     * @param _newLocked The LockedBalance with zero balances updated through this function
     * @param amount The amount to lock and stake
     */
    function _lock(
        address account,
        LockedBalance memory _newLocked,
        uint256 amount
    ) internal {
        //@notice: newLock.end is always greater than block.timestamp
        uint256 lockPeriod = _newLocked.end - block.timestamp;
        uint256 lockPeriodWeight = _calculateLockWeight(amount, lockPeriod);
        if (amount > 0) {
            _newLocked.amountOfXDC += BoringMath.to128(amount);
        }
        locks[account].push(_newLocked);
        //+1 index
        uint256 newLockId = locks[account].length;
        _stake(account, amount, lockPeriodWeight, newLockId);
    }

    /**
     * @dev Unlocks the lockId position and unstakes it from staking pool
     * @dev Updates Governance weights after unlocking
     * WARNING: rewards are not claimed during unlock.
       The UI must make sure to claim rewards before unstaking.
       Unclaimed rewards will be lost.
      `_before()` must be called before `_unlock` to update streams rps
     * @notice lockId is index + 1 of array of Locked Balance
     * @notice If the lock position is completely unlocked then the last lock is swapped with current locked
     * and last lock is popped off.
     * @param lockId the lock id of the locked position to unlock
     * @param account The address of owner of the lock
     */
    function _unlock(
        uint256 lockId,
        address account
    ) internal {

        User storage userAccount = users[account];
        LockedBalance storage updateLock = locks[account][lockId - 1];
        uint256 stakeValue = (totalAmountOfStakedXDC * updateLock.XDCShares) / totalXDCShares;
        uint256 nLockedVeXDC = updateLock.amountOfveXDC;
        
        _unstake(updateLock, stakeValue, lockId, account);
    }

    /**
     * @dev Stakes the whole lock position and calculates Stream Shares and Main Token Shares
            for the lock position to distribute rewards based on it
     * @notice autocompounding feature is implemented through amountOfMainTokenShares
     * @notice the amount of stream shares you receive decreases from 100% to 25%
     * @notice the amount of stream shares you receive depends upon when in the timeline you have staked
     * @param account The account for which the lock position is staked
     * @param amount The amount of lock position to stake
     * @param nVeXDC The amount of vote tokens released
     * @param lockId The lock id of the lock position
     */ 
    function _stake(
        address account,
        uint256 amount,
        uint256 nVeXDC,
        uint256 lockId
    ) internal {
        User storage userAccount = users[account];
        LockedBalance storage lock = locks[account][lockId - 1];

        uint256 amountOfXDCShares = _caclulateAutoCompoundingShares(amount);

        totalAmountOfStakedXDC += amount;
        totalXDCShares += amountOfXDCShares;

        uint256 weightedAmountOfSharesPerStream = _weightedShares(amountOfXDCShares, nVeXDC, block.timestamp);

        totalStreamShares += weightedAmountOfSharesPerStream;

        lock.positionStreamShares += BoringMath.to128(weightedAmountOfSharesPerStream);
        lock.XDCShares += BoringMath.to128(amountOfXDCShares);

        uint256 streamsLength = streams.length;
        for (uint256 i = 1; i < streamsLength; i++) {
            userAccount.rpsDuringLastClaimForLock[lockId][i] = streams[i].rps;
        }

        emit Staked(account, weightedAmountOfSharesPerStream, lockId);
    }

    /// WARNING: rewards are not claimed during unstake.
    /// The UI must make sure to claim rewards before unstaking.
    /// Unclaimed rewards will be lost.
    /// `_before()` must be called before `_unstake` to update streams rps
    /**
     * @dev Unstakes the amount that you want to unstake and reapplies the shares to remaining stake value
     * @param updateLock The storage reference to the lock which gets updated
     * @param stakeValue The total stake of the lock position
     * @param lockId The lock id of the lock position
     * @param account The account whose lock position is to be unstaked
     */
    function _unstake(
        LockedBalance storage updateLock,
        uint256 stakeValue,
        uint256 lockId,
        address account
    ) internal {
        User storage userAccount = users[account];

        totalAmountOfStakedXDC -= stakeValue;
        totalStreamShares -=  updateLock.positionStreamShares;
        totalXDCShares -= updateLock.XDCShares;

        userAccount.pendings[0] += stakeValue;
        userAccount.releaseTime[0] = block.timestamp + streams[0].tau;
        emit Unstaked(account, stakeValue, lockId);

        _removeLockPosition(userAccount, account, lockId);
    }

    /**
     @dev Used to unlock a position early with penalty
     @dev This unlocks and unstakes the position completely and then applies penalty
     @notice The weighing function decreases based upon the remaining time left in the lock
     @notice The penalty is decreased from the pendings of XDC stream
     @notice Early unlock completely unlocks your whole position and vote tokens
     @param lockId The lock id of lock position to early unlock
     @param account The account whose lock position is unlocked early
     */
    function _earlyUnlock(
        uint256 lockId,
        address account
    ) internal {
        LockedBalance storage lock = locks[account][lockId - 1];
        uint256 lockEnd = lock.end;
        uint256 amount = (totalAmountOfStakedXDC * lock.XDCShares) / totalXDCShares;
        _unlock(lockId, account);

        uint256 weighingCoef = _weightedPenalty(lockEnd, block.timestamp);

        uint256 penalty = (weighingCoef * amount) / 100000;

        User storage userAccount = users[account];

        require(userAccount.pendings[0] >= penalty, "penalty high");
        userAccount.pendings[0] -= penalty;
        totalPenaltyBalance += penalty;
        
    }


    function _removeLockPosition(
        User storage userAccount,
        address account,
        uint256 lockId
    ) internal {
        uint256 streamsLength = streams.length;
        uint256 lastLockId = locks[account].length;
        if (lastLockId != lockId && lastLockId > 1) {
            LockedBalance storage lastIndexLockedBalance = locks[account][lastLockId - 1];
            locks[account][lockId - 1] = lastIndexLockedBalance;
            for (uint256 i = 1; i < streamsLength; i++) {
                userAccount.rpsDuringLastClaimForLock[lockId][i] = userAccount.rpsDuringLastClaimForLock[lastLockId][i];
            }
        }
        for (uint256 i = 1; i < streamsLength; i++) {
            delete userAccount.rpsDuringLastClaimForLock[lastLockId][i];
        }
        locks[account].pop();
    }

    /**
     * @dev withdraw stream rewards after the release time.
     * @param streamId the stream index
     */
    function _withdraw(uint256 streamId) internal {
        User storage userAccount = users[msg.sender];
        uint256 pendingAmount = userAccount.pendings[streamId];
        userAccount.pendings[streamId] = 0;
        emit Released(streamId, msg.sender, pendingAmount);
        IVault(vault).payRewards(msg.sender, streams[streamId].rewardToken, pendingAmount);
    }

    function _withdrawPenalty(address accountTo) internal {
        uint256 pendingPenalty = totalPenaltyBalance;
        totalPenaltyBalance = 0;
        totalPenaltyReleased += pendingPenalty;
        IVault(vault).payRewards(accountTo, wXDC, pendingPenalty);
    }


    /**
     * @dev calculate the weighted stream shares at given timeshamp.
     * @param amountOfXDCShares The amount of Shares a user has
     * @param nVeXDC The amount of Vote token for which shares will be calculated
     * @param timestamp the timestamp refering to the current or older timestamp
     */
    function _weightedShares(
        uint256 amountOfXDCShares,
        uint256 nVeXDC,
        uint256 timestamp
    ) internal view returns (uint256) {
        ///@notice Shares accomodate vote the amount of  XDCShares and vote Tokens to be released
        ///@notice This formula makes it so that both the time locked for Main token and the amount of token locked
        ///        is used to calculate rewards
        uint256 shares = amountOfXDCShares + (voteShareCoef * nVeXDC) / 1000;

        uint256 slopeStart = streams[0].schedule.time[0] + ONE_MONTH;
        uint256 slopeEnd = slopeStart + ONE_YEAR;
        if (timestamp <= slopeStart) return shares * weight.maxWeightShares;
        if (timestamp >= slopeEnd) return shares * weight.minWeightShares;
        return
            shares *
            weight.maxWeightShares +
            (shares * (weight.maxWeightShares - weight.minWeightShares) * (slopeEnd - timestamp)) /
            (slopeEnd - slopeStart);
    }

    /**
     * @dev calculate auto compounding shares
     * @notice totalAmountOfStakedXDC => increases when Main tokens are rewarded.(_before())
     * @notice thus amount of shares for new user, decreases.
     * @notice creating compound affect for users already staking.
     */
    function _caclulateAutoCompoundingShares(uint256 amount) internal view returns (uint256) {
        uint256 _amountOfShares = 0;
        if (totalXDCShares == 0) {
            _amountOfShares = amount;
        } else {
            uint256 numerator = amount * totalXDCShares;
            _amountOfShares = numerator / totalAmountOfStakedXDC;
            if (_amountOfShares * totalAmountOfStakedXDC < numerator) {
                _amountOfShares += 1;
            }
        }

        return _amountOfShares;
    }

    function _getVaultBalance(address token) internal view returns (uint256) {
        return IERC20(token).balanceOf(vault);
    }

    /**
     * @dev Calculates the penalty for early withdrawal
     * @notice The penalty decreases linearly over time
     * @notice The penalty depends upon the remaining time for opening of lock
     * @param lockEnd The timestamp when the lock will open
     * @param timestamp The current timestamp to calculate the remaining time
     */
    function _weightedPenalty(uint256 lockEnd, uint256 timestamp) internal view returns (uint256) {
        uint256 slopeStart = lockEnd;
        uint256 remainingTime = slopeStart - timestamp;
        //why weight multiplier: Because if a person remaining time is less than 12 hours, the calculation
        //would only give minWeightPenalty, because 2900 * 12hours/4days = 0
        if (timestamp >= slopeStart) return 0;
        return (weight.penaltyWeightMultiplier *
            weight.minWeightPenalty +
            (weight.penaltyWeightMultiplier * (weight.maxWeightPenalty - weight.minWeightPenalty) * remainingTime) /
            MAX_LOCK);
    }

    /**
     * @dev calculate the governance tokens to release
     * @notice
     */
    function _calculateLockWeight(uint256 amount, uint256 lockingPeriod) internal view returns (uint256 nVeXDC) {
        //voteWeight = 365 * 24 * 60 * 60;
        nVeXDC = (amount * lockingPeriod * POINT_MULTIPLIER) / voteLockWeight / POINT_MULTIPLIER;
        return nVeXDC;
    }
}
