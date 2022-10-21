// SPDX-License-Identifier: AGPL 3.0
// Original Copyright Aurora
// Copyright Fathom 2022

pragma solidity ^0.8.13;

enum XDCStreamStatus {
    INACTIVE,
    PROPOSED,
    ACTIVE
}

struct XDCSchedule {
    uint256[] time;
    uint256[] reward;
}

struct XDCUser {
    mapping(uint256 => uint256) pendings; // The amount of tokens pending release for user per stream
    mapping(uint256 => uint256) releaseTime; // The release moment per stream
    mapping(uint256 => mapping(uint256 => uint256)) rpsDuringLastClaimForLock;
}

struct XDCWeight {
    uint32 maxWeightShares;
    uint32 minWeightShares;
    uint32 maxWeightPenalty;
    uint32 minWeightPenalty;
    uint32 penaltyWeightMultiplier;
}

struct XDCLockedBalance {
    uint128 amountOfXDC;
    uint128 positionStreamShares;
    uint64 end;
    address owner;
}
struct XDCStream {
    address owner; // stream owned by the ERC-20 reward token owner
    address manager; // stream manager handled by XDC stream manager role
    address rewardToken;
    uint256 rewardDepositAmount;
    uint256 rewardClaimedAmount;
    uint256 maxDepositAmount;
    uint256 minDepositAmount;
    uint256 tau; // pending time prior reward release
    uint256 rps; // Reward per share for a stream j>0
    XDCSchedule schedule;
    XDCStreamStatus status;
}
