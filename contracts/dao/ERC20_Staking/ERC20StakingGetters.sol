// SPDX-License-Identifier: AGPL 3.0
// Original Copyright Aurora
// Copyright Fathom 2022

pragma solidity ^0.8.13;
import "./ERC20StakingStorage.sol";
import "./interfaces/IERC20StakingGetter.sol";
import "./ERC20StakingInternals.sol";

contract ERC20StakingInitPackageGetter is ERC20StakingStorage, IERC20StakingGetter, ERC20StakingInternals {
    function getLatestRewardsPerShare(uint256 streamId) external view override returns (uint256) {
        return _getLatestRewardsPerShare(streamId);
    }

    function getLockInfo(address account, uint256 lockId) external view override returns (ERC20LockedBalance memory) {
        require(lockId <= locks[account].length, "out of index");
        return locks[account][lockId - 1];
    }

    function getStreamLength() external override view returns (uint256) {
        return streams.length;
    }

    function getUsersPendingRewards(address account, uint256 streamId) external view override returns (uint256) {
        return users[account].pendings[streamId];
    }

    function getAllLocks(address account)  external view override returns (ERC20LockedBalance[] memory) {
        return locks[account];
    }

    function getStreamClaimableAmountPerLock(uint256 streamId, address account, uint256 lockId)
        external
        view
        override
        returns (uint256) 
    {
        require(lockId <= locks[account].length, "out of index");
        uint256 latestRps = _getLatestRewardsPerShare(streamId);
        ERC20User storage userAccount = users[account];
        ERC20LockedBalance storage lock = locks[account][lockId-1];
        uint256 userRpsPerLock = userAccount.rpsDuringLastClaimForLock[lockId][streamId];
        uint256 userSharesOfLock = lock.positionStreamShares;
        return ((latestRps - userRpsPerLock) * userSharesOfLock)/RPS_MULTIPLIER;
    }
    


    /// @dev gets the user's stream pending reward
    /// @param streamId stream index
    /// @param account user account
    /// @return user.pendings[streamId]
    function getPending(uint256 streamId, address account) 
        external
        view
        override
        returns (uint256)
    {
        return users[account].pendings[streamId];
    } 


    /// @dev get the stream data
    /// @notice this function doesn't return the stream
    /// schedule due to some stake slots limitations. To
    /// get the stream schedule, refer to getStreamSchedule
    /// @param streamId the stream index
    function getStream(uint256 streamId)
        external
        view
        override
        returns (
            address streamOwner,
            address rewardToken,
            uint256 rewardDepositAmount,
            uint256 rewardClaimedAmount,
            uint256 maxDepositAmount,
            uint256 rps,
            uint256 tau,
            ERC20StreamStatus status
        )
    {
        ERC20Stream storage stream = streams[streamId];
        return (
            stream.owner,
            stream.rewardToken,
            stream.rewardDepositAmount,
            stream.rewardClaimedAmount,
            stream.maxDepositAmount,
            stream.rps,
            stream.tau,
            stream.status
        );
    }

}
