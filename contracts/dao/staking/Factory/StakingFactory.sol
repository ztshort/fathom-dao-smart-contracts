pragma solidity ^0.8.0;
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


contract StakingFactory {
    bytes32 internal constant FTHMSTAKING = keccak256("FTHM_STAKING");
    bytes32 internal constant XDCSTAKING = keccak256("XDC_STAKING");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    event StakingCreated(address indexed owner, address indexed addr, address template);
    
    
    
    struct Staking {
        bool exists;
        bytes32 templateId;
    }

    bool private initialised;
    address[] public stakingAddresses;
    mapping(bytes32 => address) private FTHMStakingAddress;
    mapping(bytes32 => address payable) private XDCStakingAddress;
    mapping(address => address) private vaultAddress;
    mapping(address =>  Staking) private stakingInfo;
    address[] private stakings;
    using SafeERC20 for IERC20;
    function initStakingFactory() external{

    }

    function deployStaking(
        bytes32 templateId,
        address _template
    ) public returns (address staking){
        address stakingTemplate = _template;
        staking = Clones.clone(stakingTemplate);
        stakingInfo[staking] = Staking(true, templateId);
        stakings.push(staking);
        emit StakingCreated(msg.sender, address(staking), stakingTemplate);
    }


    function createStakingFTHM(
                address vault,
                address fthmToken,
                address veFTHM,
                Weight memory weight,
                address streamOwner,
                uint256[] memory scheduleTimes,
                uint256[] memory scheduleRewards,
                uint256 tau,
                uint256 voteShareCoef,
                uint256 voteLockWeight,
                uint256 maxLocks
                ) internal {
        StakingPackage FTHMStaking = new StakingPackage();
        stakingInfo[address(FTHMStaking)] = Staking(true, FTHMSTAKING);
        stakings.push(address(FTHMStaking));
        FTHMStakingAddress[FTHMSTAKING] = address(FTHMStaking);

        require(vault != address(0x00),"vault address 0");
        
        //TODO: Vote Token Minter role? Need to have this as admin? Or do it later?
        IAccessControl(veFTHM).grantRole(MINTER_ROLE, address(FTHMStaking));
        //TODO: Transfer FTHM Token to vault
        IERC20(fthmToken).safeTransferFrom(
            msg.sender,
            address(this),
            scheduleRewards[0]
        );

        
        IVault(vault).addSupportedToken(fthmToken);
        IERC20(fthmToken).safeTransferFrom(
            address(this),
            vault,
            scheduleRewards[0]
        );
        //TODO  Initialize staking
        FTHMStaking.initializeStaking(
            vault,
            fthmToken,
            veFTHM,
            weight,
            streamOwner,
            scheduleTimes,
            scheduleRewards,
            tau,
            voteShareCoef,
            voteLockWeight,
            maxLocks
        ); 

    }

    function createStakingXDC(
        bytes32 templateId,
        address vault,
        address wXDC,
        XDCWeight memory weight,
        address streamOwner,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        uint256 tau,
        uint256 lockShareCoef,
        uint256 lockPeriodCoef,
        uint256 maxLocks) internal {
        address template = XDCStakingAddress[templateId];
        require(template != address(0),"staking template: addr 0");
        address staking = deployStaking(templateId, template);
        //TODO: Transfer WXDC Token to vault

        //TODO: Add supported token WXDC Token
        // Initialize staking
        IXDCStaking(staking).initializeStaking(
            vault,
            wXDC,
            weight,
            streamOwner,
            scheduleTimes,
            scheduleRewards,
            tau,
            lockShareCoef,
            lockPeriodCoef,
            maxLocks
        );
    }

    

    function createStreamFTHMStaking(
        address streamOwner,
        address rewardToken,
        uint256 maxDepositAmount,
        uint256 minDepositAmount,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        uint256 tau,
        uint256 rewardTokenAmount
    ) external {
        StakingPackage staking = StakingPackage(FTHMStakingAddress[FTHMSTAKING]);
        IVault vault = IVault(vaultAddress[address(staking)]);
        vault.addSupportedToken(rewardToken);
        
        staking.proposeStream(streamOwner, 
                              rewardToken, 
                              maxDepositAmount, 
                              minDepositAmount, 
                              scheduleTimes, 
                              scheduleRewards, 
                              tau);

        IERC20(rewardToken).safeTransferFrom(
            msg.sender,
            address(this),
            rewardTokenAmount
        );
        IERC20(rewardToken).safeApprove(
            address(staking),
            rewardTokenAmount
        );
        uint256 streamId = staking.getStreamLength();
        staking.createStream(streamId, rewardTokenAmount);
    }

    function createStreamXDCStaking(
        address streamOwner,
        address rewardToken,
        uint256 maxDepositAmount,
        uint256 minDepositAmount,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        uint256 tau,
        uint256 rewardTokenAmount
    ) external {
        XDCStakingHandler staking = XDCStakingHandler(XDCStakingAddress[XDCSTAKING]);
        IVault vault = IVault(vaultAddress[address(staking)]);
        vault.addSupportedToken(rewardToken);
        
        staking.proposeStream(streamOwner, 
                              rewardToken, 
                              maxDepositAmount, 
                              minDepositAmount, 
                              scheduleTimes, 
                              scheduleRewards, 
                              tau);

        IERC20(rewardToken).safeTransferFrom(
            msg.sender,
            address(this),
            rewardTokenAmount
        );
        IERC20(rewardToken).safeApprove(
            address(staking),
            rewardTokenAmount
        );
        uint256 streamId = staking.getStreamLength();
        staking.createStream(streamId, rewardTokenAmount);
    }

    
}