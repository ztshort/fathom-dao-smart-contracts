// SPDX-License-Identifier: AGPL 3.0
// Original Copyright Aurora
// Copyright Fathom 2022

pragma solidity ^0.8.13;
import "./XDCStakingStorage.sol";
import "./interfaces/IXDCStakingHandler.sol";
import "./XDCStakingInternals.sol";
import "../staking/vault/interfaces/IVault.sol";
import "../staking/utils/ReentrancyGuard.sol";
import "../staking/utils/AdminPausable.sol";

// solhint-disable not-rely-on-time
contract XDCStakingHandlers is XDCStakingStorage, IXDCStakingHandler,  XDCStakingInternals, ReentrancyGuard, 
                            AdminPausable {

    bytes32 public constant STREAM_MANAGER_ROLE =
        keccak256("STREAM_MANAGER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    
    /**
    * @dev initialize the contract and deploys the first stream of rewards(MAINTkn)
    * @dev initializable only once due to stakingInitialised flag
    * @notice By calling this function, the deployer of this contract must
    * make sure that the MAINTkn Rewards amount was deposited to the treasury contract
    * before initializing of the default MAINTkn Stream
    * @param _vault The Vault address to store MAINTkn and rewards tokens
    * @param _mainTkn token contract address
    * @param _weight Weighting coefficient for shares and penalties
    * @param streamOwner the owner and manager of the MAINTkn stream
    * @param scheduleTimes init schedules times
    * @param scheduleRewards init schedule rewards
    * @param tau release time constant per stream
    */
    function initializeStaking(
        address _vault,
        address _mainTkn,
        Weight memory _weight,
        address streamOwner,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        uint256 tau,
        uint256 _voteShareCoef,
        uint256 _voteLockWeight,
        uint256 _maxLocks
    ) external override {
        require(!stakingInitialised, "Already intiailised");
        _validateStreamParameters(
            streamOwner,
            _mainTkn,
            scheduleRewards[0],
            scheduleRewards[0],
            scheduleTimes,
            scheduleRewards,
            tau
        );
        _initializeStaking(_mainTkn, _weight, _vault,_voteShareCoef, _voteLockWeight, _maxLocks);
        require(IVault(vault).isSupportedToken(_mainTkn), "Unsupported token");
        pausableInit(0);
        _grantRole(STREAM_MANAGER_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
        uint256 streamId = 0;
        Schedule memory schedule = Schedule(scheduleTimes, scheduleRewards);
        streams.push(
            Stream({
                owner: streamOwner,
                manager: streamOwner,
                rewardToken: mainTkn,
                maxDepositAmount: 0,
                minDepositAmount: 0,
                rewardDepositAmount: 0,
                rewardClaimedAmount: 0,
                schedule: schedule,
                status: StreamStatus.ACTIVE,
                tau: tau,
                rps: 0
            })
        );
        earlyWithdrawalFlag = true;
        stakingInitialised = true;
        emit StreamProposed(streamId, streamOwner, _mainTkn, scheduleRewards[0]);
        emit StreamCreated(streamId, streamOwner, _mainTkn, scheduleRewards[0]);
    }

    
    function proposeStream(
        address streamOwner,
        address rewardToken,
        uint256 maxDepositAmount,
        uint256 minDepositAmount,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        uint256 tau
    ) external override onlyRole(STREAM_MANAGER_ROLE){
        _validateStreamParameters(
            streamOwner,
            rewardToken,
            maxDepositAmount,
            minDepositAmount,
            scheduleTimes,
            scheduleRewards,
            tau
        );
        // check mainTkn token address is supportedToken in the treasury
        require(IVault(vault).isSupportedToken(rewardToken), "Unsupport Token");
        Schedule memory schedule = Schedule(scheduleTimes, scheduleRewards);
        uint256 streamId = streams.length;
        streams.push(
            Stream({
                owner: streamOwner,
                manager: msg.sender,
                rewardToken: rewardToken,
                maxDepositAmount: maxDepositAmount,
                minDepositAmount: minDepositAmount,
                rewardDepositAmount: 0,
                rewardClaimedAmount: 0,
                schedule: schedule,
                status: StreamStatus.PROPOSED,
                tau: tau,
                rps: 0
            })
        );
        emit StreamProposed(streamId, streamOwner, rewardToken, maxDepositAmount);
    }

    /**
     * @dev create new stream (only stream owner)
     * stream owner must approve reward tokens to this contract.
     * @param streamId stream id
     */
    function createStream(uint256 streamId, uint256 rewardTokenAmount) external override pausable(1) {
        Stream storage stream = streams[streamId];
        require(stream.status == StreamStatus.PROPOSED, "Stream nt proposed");
        require(stream.schedule.time[0] >= block.timestamp, "Stream proposal expire");

        require(rewardTokenAmount <= stream.maxDepositAmount, "Rewards high");
        require(rewardTokenAmount >= stream.minDepositAmount, "Rewards low");

        stream.status = StreamStatus.ACTIVE;

        stream.rewardDepositAmount = rewardTokenAmount;
        if (rewardTokenAmount < stream.maxDepositAmount) {
            _updateStreamsRewardsSchedules(streamId, rewardTokenAmount);
        }
        require(stream.schedule.reward[0] == stream.rewardDepositAmount, "invalid start point");

        emit StreamCreated(streamId, stream.owner, stream.rewardToken, rewardTokenAmount);

        IERC20(stream.rewardToken).transferFrom(msg.sender, address(vault), rewardTokenAmount);
    }

    //STREAM_MANAGER_ROLE
    function cancelStreamProposal(uint256 streamId) external override onlyRole(STREAM_MANAGER_ROLE){
        Stream storage stream = streams[streamId];
        require(stream.status == StreamStatus.PROPOSED, "stream nt proposed");
        // cancel pa proposal
        stream.status = StreamStatus.INACTIVE;

        emit StreamProposalCancelled(streamId, stream.owner, stream.rewardToken);
    }

    // STREAM_MANAGER_ROLE
    /// @dev removes a stream (only default admin role)
    /// @param streamId stream index
    function removeStream(uint256 streamId, address streamFundReceiver) external override onlyRole(STREAM_MANAGER_ROLE){
        require(streamId != 0, "Stream 0");
        Stream storage stream = streams[streamId];
        require(stream.status == StreamStatus.ACTIVE, "No Stream");
        stream.status = StreamStatus.INACTIVE;
        uint256 releaseRewardAmount = stream.rewardDepositAmount - stream.rewardClaimedAmount;
        uint256 rewardTreasury = _getVaultBalance(stream.rewardToken);

        IVault(vault).payRewards(
            streamFundReceiver,
            stream.rewardToken,
            releaseRewardAmount <= rewardTreasury ? releaseRewardAmount : rewardTreasury // should not happen
        );

        emit StreamRemoved(streamId, stream.owner, stream.rewardToken);
    }
    /**
     * @dev This function claims rewards of a stream for a lock position and adds to pending of user.
     * @param streamId The id of the stream to claim rewards from
     * @param lockId The position of lock to claim rewards
     */
    function claimRewards(uint256 streamId, uint256 lockId) external override pausable(1) {
        require(lockId <= locks[msg.sender].length, "invalid lockid");
        _before();
        _moveRewardsToPending(msg.sender, streamId, lockId);
    }

    /**
     * @dev This function claims all the rewards for lock position and adds to pending of user.
     * @param lockId The position of lock to claim rewards
     */
    function claimAllStreamRewardsForLock(uint256 lockId) external override pausable(1) {
        require(lockId <= locks[msg.sender].length, "invalid lockid");
        _before();
        // Claim all streams while skipping inactive streams.
        _moveAllStreamRewardsToPending(msg.sender, lockId);
    }

    function claimAllLockRewardsForStream(uint256 streamId) external override pausable(1) {
        _before();
        _moveAllLockPositionRewardsToPending(msg.sender, streamId);
    }


    /**
     * @dev withdraw amount in the pending pool. User should wait for
     * pending time (tau constant) in order to be able to withdraw.
     * @param streamId stream index
     */
    function withdraw(uint256 streamId) external override pausable(1) {
        require(block.timestamp > users[msg.sender].releaseTime[streamId], "not released yet");
        _withdraw(streamId);
    }

    /**
     * @dev withdraw all claimed balances which have passed pending periode.
     * This function will reach gas limit with too many streams,
     * so the frontend will allow individual stream withdrawals and disable withdrawAll.
     */
    function withdrawAll() external override pausable(1) {
        User storage userAccount = users[msg.sender];
        uint256 streamsLength = streams.length;
        for (uint256 i = 0; i < streamsLength; i++) {
            if (userAccount.pendings[i] != 0 && block.timestamp > userAccount.releaseTime[i]) {
                _withdraw(i);
            }
        }
    }

    
 
}
