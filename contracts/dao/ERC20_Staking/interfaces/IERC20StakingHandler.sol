// SPDX-License-Identifier: AGPL 3.0
// Copyright Fathom 2022

pragma solidity ^0.8.13;

import "../ERC20StakingStructs.sol";

interface IERC20StakingHandler {
    

    function initializeStaking(
        address _vault,
        address _wERC20,
        ERC20Weight memory _weight,
        address streamOwner,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        uint256 tau,
        uint256 _lockShareCoef,
        uint256 _lockPeriodCoef,
        uint256 _maxLocks) external;

    function proposeStream(
        address streamOwner,
        address rewardToken,
        uint256 maxDepositAmount,
        uint256 minDepositAmount,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        uint256 tau
    ) external;

    function createStream(uint256 streamId, uint256 rewardTokenAmount) external;

    function cancelStreamProposal(uint256 streamId) external;

    function claimRewards(uint256 streamId, uint256 lockId) external;

    function removeStream(uint256 streamId, address streamFundReceiver) external;

    function claimAllStreamRewardsForLock(uint256 lockId) external;

    //function batchClaimRewards(uint256[] calldata streamIds, uint256 lockId) external;

    function withdraw(uint256 streamId) external;

    function withdrawAll() external;

    function claimAllLockRewardsForStream(uint256 streamId) external;

     /// @notice Create a new lock.
    /// @dev This will crate a new lock and deposit ERC20 to ERC20Staking
    
    function createLock(uint256 amount, uint256 unlockTime) external;
    function unlock(uint256 lockId) external;
    function earlyUnlock(uint256 lockId) external;


}
