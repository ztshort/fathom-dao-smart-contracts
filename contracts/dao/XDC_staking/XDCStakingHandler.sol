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
import "./tokens/IWXDC.sol";

// solhint-disable not-rely-on-time
//TODO Auto Compounding: Do it or not?
contract XDCStakingHandler is XDCStakingStorage, IXDCStakingHandler,  XDCStakingInternals, ReentrancyGuard, 
                            AdminPausable {

    bytes32 public constant STREAM_MANAGER_ROLE =
        keccak256("STREAM_MANAGER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    
    /**
    * @dev initialize the contract and deploys the first stream of rewards(XDC)
    * @dev initializable only once due to stakingInitialised flag
    * @notice By calling this function, the deployer of this contract must
    * make sure that the XDC Rewards amount was deposited to the treasury contract
    * before initializing of the default XDC Stream
    * @param _vault The Vault address to store XDC and rewards tokens
    * @param _wXDC token contract address
    * @param _weight Weighting coefficient for shares and penalties
    * @param streamOwner the owner and manager of the XDC stream
    * @param scheduleTimes init schedules times
    * @param scheduleRewards init schedule rewards
    * @param tau release time constant per stream
    */
    function initializeStaking(
        address _vault,
        address _wXDC,
        XDCWeight memory _weight,
        address streamOwner,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        uint256 tau,
        uint256 _lockShareCoef,
        uint256 _lockPeriodCoef,
        uint256 _maxLocks
    ) external override {
        require(!stakingInitialised, "Already intiailised");
        _validateStreamParameters(
            streamOwner,
            _wXDC,
            scheduleRewards[0],
            scheduleRewards[0],
            scheduleTimes,
            scheduleRewards,
            tau
        );
        _initializeStaking(_wXDC, _weight, _vault,_lockShareCoef, _lockPeriodCoef, _maxLocks);
        require(IVault(vault).isSupportedToken(_wXDC), "Unsupported token");
        pausableInit(0);
        _grantRole(STREAM_MANAGER_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
        uint256 streamId = 0;
        XDCSchedule memory schedule = XDCSchedule(scheduleTimes, scheduleRewards);
        streams.push(
            XDCStream({
                owner: streamOwner,
                manager: streamOwner,
                rewardToken: wXDC,
                maxDepositAmount: 0,
                minDepositAmount: 0,
                rewardDepositAmount: 0,
                rewardClaimedAmount: 0,
                schedule: schedule,
                status: XDCStreamStatus.ACTIVE,
                tau: tau,
                rps: 0
            })
        );
        earlyWithdrawalFlag = true;
        stakingInitialised = true;
        emit StreamProposed(streamId, streamOwner, _wXDC, scheduleRewards[0]);
        emit StreamCreated(streamId, streamOwner, _wXDC, scheduleRewards[0]);
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
        // check wXDC token address is supportedToken in the treasury
        require(IVault(vault).isSupportedToken(rewardToken), "Unsupport Token");
        XDCSchedule memory schedule = XDCSchedule(scheduleTimes, scheduleRewards);
        uint256 streamId = streams.length;
        streams.push(
            XDCStream({
                owner: streamOwner,
                manager: msg.sender,
                rewardToken: rewardToken,
                maxDepositAmount: maxDepositAmount,
                minDepositAmount: minDepositAmount,
                rewardDepositAmount: 0,
                rewardClaimedAmount: 0,
                schedule: schedule,
                status: XDCStreamStatus.PROPOSED,
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
        XDCStream storage stream = streams[streamId];
        require(stream.status == XDCStreamStatus.PROPOSED, "Stream nt proposed");
        require(stream.schedule.time[0] >= block.timestamp, "Stream proposal expire");

        require(rewardTokenAmount <= stream.maxDepositAmount, "Rewards high");
        require(rewardTokenAmount >= stream.minDepositAmount, "Rewards low");

        stream.status = XDCStreamStatus.ACTIVE;

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
        XDCStream storage stream = streams[streamId];
        require(stream.status == XDCStreamStatus.PROPOSED, "stream nt proposed");
        // cancel pa proposal
        stream.status = XDCStreamStatus.INACTIVE;

        emit StreamProposalCancelled(streamId, stream.owner, stream.rewardToken);
    }

    // STREAM_MANAGER_ROLE
    /// @dev removes a stream (only default admin role)
    /// @param streamId stream index
    function removeStream(uint256 streamId, address streamFundReceiver) external override onlyRole(STREAM_MANAGER_ROLE){
        require(streamId != 0, "Stream 0");
        XDCStream storage stream = streams[streamId];
        require(stream.status == XDCStreamStatus.ACTIVE, "No Stream");
        stream.status = XDCStreamStatus.INACTIVE;
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
     * @dev Creates a new lock position with lock period of unlock time
     * @param unlockTime the locking period
     */
   
    function createLock(uint256 unlockTime) external payable override nonReentrant pausable(1) {
        require(locks[msg.sender].length <= maxLockPositions, "max locks");
        uint256 xdcAmount = msg.value;
        
        require(xdcAmount > 0, "amount 0");
        require(unlockTime > block.timestamp, "bad lock time");
        require(unlockTime <= block.timestamp + MAX_LOCK, "max 1 year");

        _before();
        XDCLockedBalance memory _newLock = XDCLockedBalance({
            amountOfXDC: 0,
            positionStreamShares: 0,
            end: BoringMath.to64(unlockTime),
            owner: msg.sender
        });
        _lock(msg.sender, _newLock, xdcAmount);
        
        wrapXDC(xdcAmount);
        IERC20(wXDC).transferFrom(address(this), address(vault), xdcAmount);
    }

    /**
     * @dev This function unlocks the whole position of the lock id.
     * @notice stakeValue is calcuated to balance the shares calculation
     * @param lockId The lockId to unlock completely
     */
    function unlock(uint256 lockId) external override nonReentrant pausable(1) {
        XDCLockedBalance storage lock = locks[msg.sender][lockId - 1];
        _isItUnlockable(lockId);
        require(lock.end <= block.timestamp, "lock not open");
        _before();
        _unlock(lockId, msg.sender);
    }

    /**
     * @dev This funciton allows for earlier withdrawal but with penalty
     * @param lockId The lock id to unlock early
     */
    function earlyUnlock(uint256 lockId) external override nonReentrant pausable(1) {
        XDCLockedBalance storage lock = locks[msg.sender][lockId - 1];
        _isItUnlockable(lockId);
        require(lock.end > block.timestamp, "lock opened");
        _before();
        _earlyUnlock(lockId, msg.sender);   
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
     * @dev withdraw amount in the pending pool. XDCUser should wait for
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
        XDCUser storage userAccount = users[msg.sender];
        uint256 streamsLength = streams.length;
        for (uint256 i = 0; i < streamsLength; i++) {
            if (userAccount.pendings[i] != 0 && block.timestamp > userAccount.releaseTime[i]) {
                
                _withdraw(i);
            }
        }
    }

    
    function _isItUnlockable(uint256 lockId) internal view  {
        require(lockId != 0, "lockId 0");
        require(lockId <= locks[msg.sender].length, "invalid lockid");
        XDCLockedBalance storage lock = locks[msg.sender][lockId - 1];
        require(lock.amountOfXDC > 0, "no lock amount");
        require(lock.owner == msg.sender, "bad owner");
    }
 
}
