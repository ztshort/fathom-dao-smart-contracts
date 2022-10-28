// Copyright SECURRENCY INC.
// SPDX-License-Identifier: AGPL 3.0
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/proxy/Clones.sol";
import "../../XDC_staking/interfaces/IXDCStaking.sol";
import "../interfaces/IStaking.sol";
import "../vault/interfaces/IVault.sol";
import "../packages/StakingPackage.sol";
import "../../XDC_staking/XDCStakingHandler.sol";
import "../../governance/token/ERC20/IERC20.sol";
import "../library/SafeERC20.sol";
import "../../governance/interfaces/IVeMainToken.sol";
import "../../governance/access/IAccessControl.sol";
import "../../ERC20_Staking/interfaces/IERC20Staking.sol";

interface IStakingFactory {
    struct StakingProperties{
        uint256 tau;
        uint256 lockShareCoef;
        uint256 lockPeriodCoef;
        uint256 maxLocks;
    }

    struct FTHMStakingAddresses{
        address vault;
        address fthmToken;
        address veFTHM;
    }

    struct StreamProperties {
        bytes32 templateId;
        address streamOwner;
        address rewardToken;
        uint256 maxDepositAmount;
        uint256 minDepositAmount;
        uint256 tau;
        uint256 rewardTokenAmount;
    }

    struct ERC20StakingStreamProperties {
        bytes32 templateId;
        address vault;
        address erc20;
        address streamOwner;
    }
    function initStakingFactory() external;
  
    function createStakingFTHM(
        bytes32 templateId,
        address vault,
        address fthmToken,
        address veFTHM,
        Weight memory weight,
        address streamOwner,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        StakingProperties memory stakingProps) external;

    function createStakingXDC(
        bytes32 templateId,
        address vault,
        address wXDC,
        XDCWeight memory weight,
        address streamOwner,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        StakingProperties memory stakingProps) external;
    
    function createERC20Staking(
        bytes32 templateId,
        address vault,
        address wXDC,
        ERC20Weight memory weight,
        address streamOwner,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        StakingProperties memory stakingProps) external;

    function createStreamStaking(
        bytes32 templateId,
        address streamOwner,
        address rewardToken,
        uint256 maxDepositAmount,
        uint256 minDepositAmount,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        uint256 tau,
        uint256 rewardTokenAmount) external;

    function addERC20StakingTemplate(
        bytes32 templateId,
        address staking
    ) external;
}
