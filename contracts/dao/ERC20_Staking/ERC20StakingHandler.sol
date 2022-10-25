// SPDX-License-Identifier: AGPL 3.0
// Original Copyright Aurora
// Copyright Fathom 2022

pragma solidity ^0.8.13;
import "./ERC20StakingStorage.sol";
import "./interfaces/IERC20StakingHandler.sol";
import "./ERC20StakingInternals.sol";
import "../staking/vault/interfaces/IVault.sol";
import "../staking/utils/ReentrancyGuard.sol";
import "../staking/utils/AdminPausable.sol";
import "./ERC20StakingGetters.sol";

// solhint-disable not-rely-on-time
//TODO Auto Compounding: Do it or not?
contract ERC20StakingHandler is ERC20StakingStorage, IERC20StakingHandler,  ERC20StakingInternals, ReentrancyGuard, 
                            AdminPausable,ERC20StakingInitPackageGetter {

    bytes32 public constant STREAM_MANAGER_ROLE =
        keccak256("STREAM_MANAGER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    
    /**
    * @dev initialize the contract and deploys the first stream of rewards(ERC20)
    * @dev initializable only once due to stakingInitialised flag
    * @notice By calling this function, the deployer of this contract must
    * make sure that the ERC20 Rewards amount was deposited to the treasury contract
    * before initializing of the default ERC20 Stream
    * @param _vault The Vault address to store ERC20 and rewards tokens
    * @param _wERC20 token contract address
    * @param _weight Weighting coefficient for shares and penalties
    * @param streamOwner the owner and manager of the ERC20 stream
    * @param scheduleTimes init schedules times
    * @param scheduleRewards init schedule rewards
    * @param tau release time constant per stream
    */
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
        uint256 _maxLocks
    ) external override {
        require(!stakingInitialised, "Already intiailised");
        _validateStreamParameters(
            streamOwner,
            _wERC20,
            scheduleRewards[0],
            scheduleRewards[0],
            scheduleTimes,
            scheduleRewards,
            tau
        );
        _initializeStaking(_wERC20, _weight, _vault,_lockShareCoef, _lockPeriodCoef, _maxLocks);
        require(IVault(vault).isSupportedToken(_wERC20), "Unsupported token");
        pausableInit(0);
        _grantRole(STREAM_MANAGER_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
        uint256 streamId = 0;
        ERC20Schedule memory schedule = ERC20Schedule(scheduleTimes, scheduleRewards);
        streams.push(
            ERC20Stream({
                owner: streamOwner,
                manager: streamOwner,
                rewardToken: wERC20,
                maxDepositAmount: 0,
                minDepositAmount: 0,
                rewardDepositAmount: 0,
                rewardClaimedAmount: 0,
                schedule: schedule,
                status: ERC20StreamStatus.ACTIVE,
                tau: tau,
                rps: 0
            })
        );
        earlyWithdrawalFlag = true;
        stakingInitialised = true;
        emit StreamProposed(streamId, streamOwner, _wERC20, scheduleRewards[0]);
        emit StreamCreated(streamId, streamOwner, _wERC20, scheduleRewards[0]);
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
        // check wERC20 token address is supportedToken in the treasury
        require(IVault(vault).isSupportedToken(rewardToken), "Unsupport Token");
        ERC20Schedule memory schedule = ERC20Schedule(scheduleTimes, scheduleRewards);
        uint256 streamId = streams.length;
        streams.push(
            ERC20Stream({
                owner: streamOwner,
                manager: msg.sender,
                rewardToken: rewardToken,
                maxDepositAmount: maxDepositAmount,
                minDepositAmount: minDepositAmount,
                rewardDepositAmount: 0,
                rewardClaimedAmount: 0,
                schedule: schedule,
                status: ERC20StreamStatus.PROPOSED,
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
        ERC20Stream storage stream = streams[streamId];
        require(stream.status == ERC20StreamStatus.PROPOSED, "Stream nt proposed");
        require(stream.schedule.time[0] >= block.timestamp, "Stream proposal expire");

        require(rewardTokenAmount <= stream.maxDepositAmount, "Rewards high");
        require(rewardTokenAmount >= stream.minDepositAmount, "Rewards low");

        stream.status = ERC20StreamStatus.ACTIVE;

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
        ERC20Stream storage stream = streams[streamId];
        require(stream.status == ERC20StreamStatus.PROPOSED, "stream nt proposed");
        // cancel pa proposal
        stream.status = ERC20StreamStatus.INACTIVE;

        emit StreamProposalCancelled(streamId, stream.owner, stream.rewardToken);
    }

    // STREAM_MANAGER_ROLE
    /// @dev removes a stream (only default admin role)
    /// @param streamId stream index
    function removeStream(uint256 streamId, address streamFundReceiver) external override onlyRole(STREAM_MANAGER_ROLE){
        require(streamId != 0, "Stream 0");
        ERC20Stream storage stream = streams[streamId];
        require(stream.status == ERC20StreamStatus.ACTIVE, "No Stream");
        stream.status = ERC20StreamStatus.INACTIVE;
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
   
    function createLock(uint256 amount, uint256 unlockTime) external  override nonReentrant pausable(1) {
        require(locks[msg.sender].length <= maxLockPositions, "max locks");
        
        require(amount > 0, "amount 0");
        require(unlockTime > block.timestamp, "bad lock time");
        require(unlockTime <= block.timestamp + MAX_LOCK, "max 1 year");

        _before();
        ERC20LockedBalance memory _newLock = ERC20LockedBalance({
            amountOfERC20: 0,
            positionStreamShares: 0,
            end: BoringMath.to64(unlockTime),
            owner: msg.sender
        });
        _lock(msg.sender, _newLock, amount);
        
        IERC20(wERC20).transferFrom(msg.sender, address(vault), amount);
    }

    /**
     * @dev This function unlocks the whole position of the lock id.
     * @notice stakeValue is calcuated to balance the shares calculation
     * @param lockId The lockId to unlock completely
     */
    function unlock(uint256 lockId) external override nonReentrant pausable(1) {
        ERC20LockedBalance storage lock = locks[msg.sender][lockId - 1];
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
        ERC20LockedBalance storage lock = locks[msg.sender][lockId - 1];
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
     * @dev withdraw amount in the pending pool. ERC20User should wait for
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
        ERC20User storage userAccount = users[msg.sender];
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
        ERC20LockedBalance storage lock = locks[msg.sender][lockId - 1];
        require(lock.amountOfERC20 > 0, "no lock amount");
        require(lock.owner == msg.sender, "bad owner");
    }
 
}
