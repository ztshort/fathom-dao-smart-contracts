// SPDX-License-Identifier: AGPL 3.0
// Original Copyright Aurora
// Copyright Fathom 2022

pragma solidity 0.8.13;

import "./StakingInternals.sol";
import "../StakingStorage.sol";
import "../interfaces/IStakingHandler.sol";
import "../vault/interfaces/IVault.sol";
import "../../../common/security/ReentrancyGuard.sol";
import "../../../common/security/AdminPausable.sol";

// solhint-disable not-rely-on-time
contract StakingHandlers is
    StakingStorage,
    IStakingHandler,
    StakingInternals,
    ReentrancyGuard,
    AdminPausable
{
    bytes32 public constant STREAM_MANAGER_ROLE = keccak256("STREAM_MANAGER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    /**
    * @dev initialize the contract and deploys the first stream of rewards
    * @dev initializable only once due to stakingInitialised flag
    * @notice By calling this function, the deployer of this contract must
    * make sure that the Rewards amount was deposited to the treasury contract
    * before initializing of the default Stream
    * @param _vault The Vault address to store main token and rewards tokens
    * @param _mainToken token contract address
    * @param _weight Weighting coefficient for shares and penalties
    * @param _admin the owner and manager of the main token stream
    * @param scheduleTimes init schedules times
    * @param scheduleRewards init schedule rewards
    * @param tau release time constant per stream
    */
    function initializeStaking(
        address _admin,
        address _vault,
        address _mainToken,
        address _voteToken,
        Weight calldata _weight,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        uint256 tau,
        VoteCoefficient memory voteCoef,
        uint256 _maxLocks,
        address _rewardsContract
    ) external override {
        rewardsCalculator = _rewardsContract;
        _validateStreamParameters(
            _admin,
            _mainToken,
            scheduleRewards[0],
            scheduleRewards[0],
            scheduleTimes,
            scheduleRewards,
            tau
        );

        _initializeStaking(_mainToken, _voteToken, _weight, _vault, _maxLocks, 
            voteCoef.voteShareCoef, voteCoef.voteLockCoef);
        require(IVault(vault).isSupportedToken(_mainToken), "Unsupported token");
        pausableInit(0, _admin);

        _grantRole(STREAM_MANAGER_ROLE, _admin);
        _grantRole(TREASURY_ROLE, _admin);

        uint256 streamId = 0;
        Schedule memory schedule = Schedule(scheduleTimes, scheduleRewards);
        streams.push(
            Stream({
                owner: _admin,
                manager: _admin,
                rewardToken: mainToken,
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
        maxLockPeriod = ONE_YEAR;
        emit StreamProposed(streamId, _admin, mainToken, scheduleRewards[0]);
        emit StreamCreated(streamId, _admin, mainToken, scheduleRewards[0]);
    }
    /**
     * @dev An admin of the staking contract can whitelist (propose) a stream.
     * Whitelisting of the stream provides the option for the stream
     * owner (presumably the issuing party of a specific token) to
     * deposit some ERC-20 tokens on the staking contract and potentially
     * get in return some main tokens immediately. 
     * @notice Manager of Vault must call
     * @param streamOwner only this account will be able to launch a stream
     * @param rewardToken the address of the ERC-20 tokens to be deposited in the stream
     * @param maxDepositAmount The upper amount of the tokens that should be deposited by stream owner
     * @param scheduleTimes timestamp denoting the start of each scheduled interval.
                            Last element is the end of the stream.
     * @param scheduleRewards remaining rewards to be delivered at the beginning of each scheduled interval. 
                               Last element is always zero.
     * First value (in scheduleRewards) from array is supposed to be a total amount of rewards for stream.
     * @param tau the tau is (pending release period) for this stream (e.g one day)
    */
    function proposeStream(
        address streamOwner,
        address rewardToken,
        uint256 maxDepositAmount,
        uint256 minDepositAmount,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        uint256 tau
    ) public override onlyRole(STREAM_MANAGER_ROLE) {
        _validateStreamParameters(
            streamOwner,
            rewardToken,
            maxDepositAmount,
            minDepositAmount,
            scheduleTimes,
            scheduleRewards,
            tau
        );
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

    function createStream(uint256 streamId, uint256 rewardTokenAmount) public override pausable(1) {
        Stream storage stream = streams[streamId];
        require(stream.status == StreamStatus.PROPOSED, "nt proposed");
        require(stream.schedule.time[0] >= block.timestamp, "prop expire");

        require(rewardTokenAmount <= stream.maxDepositAmount, "rwrds high");
        require(rewardTokenAmount >= stream.minDepositAmount, "rwrds low");

        stream.status = StreamStatus.ACTIVE;

        stream.rewardDepositAmount = rewardTokenAmount;
        if (rewardTokenAmount < stream.maxDepositAmount) {
            _updateStreamsRewardsSchedules(streamId, rewardTokenAmount);
        }
        require(stream.schedule.reward[0] == stream.rewardDepositAmount, "bad start point");

        emit StreamCreated(streamId, stream.owner, stream.rewardToken, rewardTokenAmount);

        IERC20(stream.rewardToken).transferFrom(msg.sender, address(vault), rewardTokenAmount);
    }

    function cancelStreamProposal(uint256 streamId) public override onlyRole(STREAM_MANAGER_ROLE) {
        Stream storage stream = streams[streamId];
        require(stream.status == StreamStatus.PROPOSED, "nt proposed");
        stream.status = StreamStatus.INACTIVE;

        emit StreamProposalCancelled(streamId, stream.owner, stream.rewardToken);
    }

    function removeStream(uint256 streamId, address streamFundReceiver)
        public
        override
        onlyRole(STREAM_MANAGER_ROLE)
    {
        require(streamId != 0, "Stream 0");
        Stream storage stream = streams[streamId];
        require(stream.status == StreamStatus.ACTIVE, "No Stream");
        stream.status = StreamStatus.INACTIVE;
        uint256 releaseRewardAmount = stream.rewardDepositAmount - stream.rewardClaimedAmount;
        uint256 rewardTreasury = IERC20(stream.rewardToken).balanceOf(vault);

        IVault(vault).payRewards(
            streamFundReceiver,
            stream.rewardToken,
            releaseRewardAmount <= rewardTreasury ? releaseRewardAmount : rewardTreasury // should not happen
        );

        emit StreamRemoved(streamId, stream.owner, stream.rewardToken);
    }

    function createLockWithoutEarlyWithdraw(
        uint256 amount,
        uint256 lockPeriod,
        address account,
        bool flag
    ) public override pausable(1) {   
        prohibitedEarlyWithdraw[account][locks[account].length + 1] = flag;
        createLock(amount, lockPeriod, account);
    } 

    function createLock(uint256 amount, uint256 lockPeriod, address account) public override nonReentrant pausable(1) {
        require(locks[account].length <= maxLockPositions, "max locks");
        require(amount > 0, "amount 0");
        require(lockPeriod <=  maxLockPeriod, "max lock period");
        _updateStreamRPS();
        _lock(account, amount,lockPeriod);
        IERC20(mainToken).transferFrom(msg.sender, address(vault), amount);
    }

    function unlock(uint256 lockId) public override nonReentrant pausable(1) {
        _verifyUnlock(lockId);
        LockedBalance storage lock = locks[msg.sender][lockId - 1];
        require(lock.end <= block.timestamp, "lock not open");
        _updateStreamRPS();
        uint256 stakeValue = (totalAmountOfStakedToken * lock.tokenShares) / totalShares;
        _unlock(stakeValue, stakeValue, lockId, msg.sender);
        _withdrawMainToken();
    }

    function unlockPartially(uint256 lockId, uint256 amount) public override nonReentrant pausable(1) {
        _verifyUnlock(lockId);
        LockedBalance storage lock = locks[msg.sender][lockId - 1];
        require(lock.end <= block.timestamp, "!lockopen");
        _updateStreamRPS();
        uint256 stakeValue = (totalAmountOfStakedToken * lock.tokenShares) / totalShares;
        _unlock(stakeValue, amount, lockId, msg.sender);
        _withdrawMainToken();
    }

    function earlyUnlock(uint256 lockId) public override nonReentrant pausable(1) {
        _verifyUnlock(lockId);
        require(prohibitedEarlyWithdraw[msg.sender][lockId] == false, "early infeasible");
        LockedBalance storage lock = locks[msg.sender][lockId - 1];
        require(lock.end > block.timestamp, "lock opened");
        _updateStreamRPS();
        _earlyUnlock(lockId, msg.sender);
        _withdrawMainToken();
    }

    function claimRewards(uint256 streamId, uint256 lockId) public override pausable(1) {
        require(lockId <= locks[msg.sender].length, "bad lockid");
        _updateStreamRPS();
        _moveRewardsToPending(msg.sender, streamId, lockId);
    }
    
    function claimAllStreamRewardsForLock(uint256 lockId) public override pausable(1) {
        require(lockId <= locks[msg.sender].length, "bad lockid");
        _updateStreamRPS();
        // Claim all streams while skipping inactive streams.
        _moveAllStreamRewardsToPending(msg.sender, lockId);
    }

    function claimAllLockRewardsForStream(uint256 streamId) public override pausable(1) {
        _updateStreamRPS();
        _moveAllLockPositionRewardsToPending(msg.sender, streamId);
    }
    /**
     * @dev withdraw amount in the pending pool. User should wait for
     * pending time (tau constant) in order to be able to withdraw.
     */
    function withdrawRewards(uint256 streamId) public override pausable(1) {
        require(block.timestamp > users[msg.sender].releaseTime[streamId], "not released");
        _withdraw(streamId);
    }

    /**
     * @dev withdraw all claimed balances which have passed pending period.
     * This function will reach gas limit with too many streams
     */
    function withdrawRewardsFromAllStreams() public override pausable(1) {
        User storage userAccount = users[msg.sender];
        for (uint256 i = 0; i < streams.length; i++) {
            if (userAccount.pendings[i] != 0 && block.timestamp > userAccount.releaseTime[i]) {
                _withdraw(i);
            }
        }
    }

    function setWeight(Weight memory _weight) override public onlyRole(DEFAULT_ADMIN_ROLE) {
        weight = _weight;
    }

    function updateVault(address _vault)
        public
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // enforce pausing this contract before updating the address.
        // This mitigates the risk of future invalid reward claims
        require(paused != 0, "required pause");
        require(_vault != address(0), "zero addr");
        require(_vault != vault, "same addr");
        vault = _vault;
    }

    function withdrawPenalty(address penaltyReceiver) public override pausable(1) onlyRole(TREASURY_ROLE) {
        require(totalPenaltyBalance > 0, "no penalty");
        _withdrawPenalty(penaltyReceiver);
    }

    function _withdrawMainToken() internal{
        // main stream id = 0
        _withdraw(0);
    }

    function _verifyUnlock(uint256 lockId) internal view  {
        require(lockId > 0,"zero lockid");
        require(lockId <= locks[msg.sender].length, "bad lockid");
        LockedBalance storage lock = locks[msg.sender][lockId - 1];
        require(lock.amountOfToken > 0, "no lock amount");
        require(lock.owner == msg.sender, "bad owner");
    }
}
