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
import "../../ERC20_Staking/interfaces/IERC20Staking.sol";



contract StakingFactory {
    bytes32 internal constant FTHMSTAKING = keccak256("FTHM_STAKING");
    bytes32 internal constant XDCSTAKING = keccak256("XDC_STAKING");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    struct StakingProperties{
        uint256 tau;
        uint256 lockShareCoef;
        uint256 lockPeriodCoef;
        uint256 maxLocks;
    }

    struct Staking {
        bool exists;
        bytes32 templateId;
    }
    event StakingCreated(address indexed owner, address indexed addr, address template);


    bool private initialised;
    address[] public stakingAddresses;
     //TODO: This needed???
    mapping(bytes32 => address) private StakingTemplateAddress;

    mapping(address => address) private vaultAddress;
    mapping(address =>  Staking) private stakingInfo;
    address[] private stakings;
    using SafeERC20 for IERC20;
    function initStakingFactory() external{

    }

    ///@notice deployStaking only for staking ERC20 tokens that is created as streams
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
        //TODO: This needed???
        StakingTemplateAddress[FTHMSTAKING] = address(FTHMStaking);

        require(vault != address(0x00),"vault address 0");
        
        //TODO: Vote Token Minter role? Need to have this as admin? Or do it later?
        IAccessControl(veFTHM).grantRole(MINTER_ROLE, address(FTHMStaking));
        //TODO: Transfer FTHM Token to vault
        IERC20(fthmToken).safeTransferFrom(
            msg.sender,
            address(this),
            scheduleRewards[0]
        );
        uint256 remainingBalance = IERC20(fthmToken).balanceOf(address(this));
        require(remainingBalance >= scheduleRewards[0],"insufficient reward tokena mount");

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

        XDCStakingHandler XDCStaking = new XDCStakingHandler();
        stakingInfo[address(XDCStaking)] = Staking(true, FTHMSTAKING);
        stakings.push(address(XDCStaking));
        //TODO: This needed???
        StakingTemplateAddress[FTHMSTAKING] = address(XDCStaking);

        //TODO: Transfer WXDC Token to vault

        //TODO: Add supported token WXDC Token
        // Initialize staking
        XDCStaking.initializeStaking(
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

    function createERC20Staking(
        bytes32 templateId,
        address vault,
        address wXDC,
        ERC20Weight memory weight,
        address streamOwner,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        StakingProperties memory stakingProps
    ) external {
        address staking = StakingTemplateAddress[templateId];
        require(staking != address(0x00),"empty staking address");
        address stakingProxy = deployStaking(templateId,staking);

        IERC20Staking stakingContract = IERC20Staking(stakingProxy);
        stakingInfo[address(staking)] = Staking(true, FTHMSTAKING);
        stakings.push(address(staking));
        //TODO: This needed???
        StakingTemplateAddress[templateId] = address(staking);

        require(vault != address(0x00),"vault address 0");
        
        //TODO: Transfer FTHM Token to vault
        IERC20(wXDC).safeTransferFrom(
            msg.sender,
            address(this),
            scheduleRewards[0]
        );
        uint256 remainingBalance = IERC20(wXDC).balanceOf(address(this));
        require(remainingBalance >= scheduleRewards[0],"insufficient reward tokena mount");

        IVault(vault).addSupportedToken(wXDC);
        IERC20(wXDC).safeTransferFrom(
            address(this),
            vault,
            scheduleRewards[0]
        );


        //TODO  Initialize staking
        stakingContract.initializeStaking(
            vault,
            wXDC,
            weight,
            streamOwner,
            scheduleTimes,
            scheduleRewards,
            stakingProps.tau,
            stakingProps.lockShareCoef,
            stakingProps.lockPeriodCoef,
            stakingProps.maxLocks
        ); 
    }

    //TODO: Think about this more.
    function createStreamStaking(
        bytes32 templateId,
        address streamOwner,
        address rewardToken,
        uint256 maxDepositAmount,
        uint256 minDepositAmount,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        uint256 tau,
        uint256 rewardTokenAmount
    ) external {
        IStaking staking = IStaking(StakingTemplateAddress[templateId]);
        IVault vault = IVault(vaultAddress[address(staking)]);
        vault.addSupportedToken(rewardToken);
        
        staking.proposeStream(streamOwner, 
                              rewardToken, 
                              maxDepositAmount, 
                              minDepositAmount, 
                              scheduleTimes, 
                              scheduleRewards, 
                              tau);

        if(rewardTokenAmount > 0){
            IERC20(rewardToken).safeTransferFrom(
                msg.sender,
                address(this),
                rewardTokenAmount
            );
        }

        uint256 remainingBalance = IERC20(rewardToken).balanceOf(address(this));
        require(remainingBalance >= rewardTokenAmount,"insufficient reward tokena mount");
        
        IERC20(rewardToken).safeApprove(
            address(staking),
            rewardTokenAmount
        );
        uint256 streamId = staking.getStreamLength();
        staking.createStream(streamId, rewardTokenAmount);
    }

    function addERC20StakingTemplate(
        bytes32 templateId,
        address staking
    ) external {
        address stakingAddr = StakingTemplateAddress[templateId];
        require(stakingAddr == address(0x00),"not empty staking address");
        StakingTemplateAddress[templateId] = staking;
    }
    
}