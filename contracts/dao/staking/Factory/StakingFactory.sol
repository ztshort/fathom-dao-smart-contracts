pragma solidity ^0.8.0;
import "@openzeppelin/contracts/proxy/Clones.sol";
import "../../XDC_staking/interfaces/IXDCStaking.sol";
import "../interfaces/IStaking.sol";
import "../vault/interfaces/IVault.sol";

import "../../governance/token/ERC20/IERC20.sol";
import "../library/SafeERC20.sol";
import "../../governance/interfaces/IVeMainToken.sol";
import "../../governance/access/IAccessControl.sol";
import "../../ERC20_Staking/interfaces/IERC20Staking.sol";
import "./IStakingFactory.sol";
import "../../governance/access/AccessControl.sol";

contract StakingFactory is IStakingFactory, AccessControl{
    using SafeERC20 for IERC20;

    struct Staking {
        bool exists;
        bytes32 templateId;
    }

    
    
    bytes32 internal constant FTHMSTAKING = keccak256("FTHM_STAKING");
    bytes32 internal constant XDCSTAKING = keccak256("XDC_STAKING");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    bool private initialised;
    address[] public stakingAddresses;
     //TODO: This needed???
    mapping(bytes32 => address) private StakingTemplateAddress;

    mapping(address => address) private vaultAddress;
    mapping(address =>  Staking) private stakingInfo;
    
    address[] private stakings;
    bytes32 public constant ADMIN_ROLE =
        keccak256("ADMIN_ROLE");
    event StakingCreated(address indexed owner, address indexed addr, address template);

    function initStakingFactory() external override{
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function createStakingFTHM(
        bytes32 templateId,
        address vault,
        address fthmToken,
        address veFTHM,
        Weight memory weight,
        address streamOwner,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        StakingProperties memory stakingProps
    ) override external  onlyRole(ADMIN_ROLE){
        
        _createStakingFTHM(
            templateId,
            vault,
            fthmToken,
            veFTHM,
            weight, 
            streamOwner, 
            scheduleTimes, 
            scheduleRewards, 
            stakingProps);
    }

    function createStakingXDC(
        bytes32 templateId,
        address vault,
        address wXDC,
        XDCWeight memory weight,
        address streamOwner,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        StakingProperties memory stakingProps
    ) override external  onlyRole(ADMIN_ROLE){
        _createStakingXDC(
            templateId,
            vault,
            wXDC,
            weight,
            streamOwner,
            scheduleTimes,
            scheduleRewards,
            stakingProps);
    }

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
    ) override external onlyRole(ADMIN_ROLE){
        _createStream(
            templateId,
            streamOwner, 
            rewardToken, 
            maxDepositAmount, 
            minDepositAmount, 
            scheduleTimes, 
            scheduleRewards, 
            tau,
            rewardTokenAmount);
    }

    function createERC20Staking(
        bytes32 templateId,
        address vault,
        address erc20,
        ERC20Weight memory weight,
        address streamOwner,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        StakingProperties memory stakingProps
    ) override external  onlyRole(ADMIN_ROLE){
        _createERC20Staking(
            templateId, 
            vault, 
            erc20, 
            weight, 
            streamOwner, 
            scheduleTimes, 
            scheduleRewards, 
            stakingProps);
    }

    function addERC20StakingTemplate(
        bytes32 templateId,
        address staking
    ) override external onlyRole(ADMIN_ROLE){
        address stakingAddr = StakingTemplateAddress[templateId];
        require(stakingAddr == address(0x00),"not empty staking address");
        StakingTemplateAddress[templateId] = staking;
    }

    ///@notice deployStaking only for staking ERC20 tokens that is created as streams
    function _deployStaking(
        bytes32 templateId,
        address _template
    ) internal returns (address staking) {
        address stakingTemplate = _template;
        //TODO: Change to ERC1967 / or Ask.
        staking = Clones.clone(stakingTemplate);
        stakingInfo[staking] = Staking(true, templateId);
        stakings.push(staking);
        emit StakingCreated(msg.sender, address(staking), stakingTemplate);
    }

    function _createStakingFTHM(
                bytes32 templateId,
                address vault,
                address fthmToken,
                address veFTHM,
                Weight memory weight,
                address streamOwner,
                uint256[] memory scheduleTimes,
                uint256[] memory scheduleRewards,
                StakingProperties memory stakingProps
                )  internal 
    {
        address staking = StakingTemplateAddress[templateId];
        require(staking != address(0x00),"empty staking address");
        IStaking FTHMStaking = IStaking(_deployStaking(templateId,staking));
        require(vault != address(0x00),"vault address 0");
        IAccessControl(veFTHM).grantRole(MINTER_ROLE, address(FTHMStaking));
        IERC20(fthmToken).safeTransferFrom(
            msg.sender,
            address(this),
            scheduleRewards[0]
        );
        uint256 remainingBalance = IERC20(fthmToken).balanceOf(address(this));
        require(remainingBalance >= scheduleRewards[0],"insufficient reward tokena mount");
        IVault(vault).addSupportedToken(fthmToken);
        //TODO: Remove This
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
            stakingProps.tau,
            stakingProps.lockShareCoef,
            stakingProps.lockPeriodCoef,
            stakingProps.maxLocks
        ); 
    }

    

    function _createStakingXDC(
        bytes32 templateId,
        address vault,
        address wXDC,
        XDCWeight memory weight,
        address streamOwner,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        StakingProperties memory stakingProps)  internal 
    {
        address staking = StakingTemplateAddress[templateId];
        require(staking != address(0x00),"empty staking address");
        address stakingProxy = _deployStaking(templateId,staking);
        IXDCStaking XDCStaking = IXDCStaking(stakingProxy);
        //TODO: Transfer WXDC Token to vault
        IERC20(wXDC).safeTransferFrom(
            msg.sender,
            address(this),
            scheduleRewards[0]
        );
        //TODO: Add supported token WXDC Token
        IVault(vault).addSupportedToken(wXDC);

        IERC20(wXDC).safeTransferFrom(
            address(this),
            vault,
            scheduleRewards[0]
        );
        // Initialize staking
        XDCStaking.initializeStaking(
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

    function _createERC20Staking(
        bytes32 templateId,
        address vault,
        address erc20,
        ERC20Weight memory weight,
        address streamOwner,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        StakingProperties memory stakingProps
    )  internal {
        address staking = StakingTemplateAddress[templateId];
        require(staking != address(0x00),"empty staking address");
        address stakingProxy = _deployStaking(templateId,staking);

        IERC20Staking stakingContract = IERC20Staking(stakingProxy);
        stakingInfo[address(staking)] = Staking(true, FTHMSTAKING);
        stakings.push(address(staking));
        //TODO: This needed???
        StakingTemplateAddress[templateId] = address(staking);

        require(vault != address(0x00),"vault address 0");
        
        //TODO: Transfer FTHM Token to vault
        IERC20(erc20).safeTransferFrom(
            msg.sender,
            address(this),
            scheduleRewards[0]
        );
        uint256 remainingBalance = IERC20(erc20).balanceOf(address(this));
        require(remainingBalance >= scheduleRewards[0],"insufficient reward tokena mount");

        IVault(vault).addSupportedToken(erc20);
        IERC20(erc20).safeTransferFrom(
            address(this),
            vault,
            scheduleRewards[0]
        );
        //TODO  Initialize staking
        stakingContract.initializeStaking(
            vault,
            erc20,
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
    function _createStream(
        bytes32 templateId,
        address streamOwner,
        address rewardToken,
        uint256 maxDepositAmount,
        uint256 minDepositAmount,
        uint256[] memory scheduleTimes,
        uint256[] memory scheduleRewards,
        uint256 tau,
        uint256 rewardTokenAmount
    )  internal {
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
        require(remainingBalance >= rewardTokenAmount,"insufficient reward token mount");
        
        IERC20(rewardToken).safeApprove(
            address(staking),
            rewardTokenAmount
        );
        uint256 streamId = staking.getStreamLength();
        staking.createStream(streamId, rewardTokenAmount);
    }
   
    function createStreamAndStaking(
        ERC20StakingStreamProperties memory stakingStreamProperties,
        ERC20Weight memory weight,
        
        StakingProperties memory stakingProps,
        uint256[] memory stakingScheduleTimes,
        uint256[] memory stakingScheduleRewards,
        uint256[] memory streamScheduleTimes,
        uint256[] memory streamScheduleRewards,
        StreamProperties memory streamProps
    ) external{
        _createStream(
            streamProps.templateId,
            streamProps.streamOwner,
            streamProps.rewardToken,
            streamProps.maxDepositAmount,
            streamProps.minDepositAmount,
            streamScheduleTimes,
            streamScheduleRewards,
            streamProps.tau,
            streamProps.rewardTokenAmount
        );

        _createERC20Staking(
            stakingStreamProperties.templateId, 
            stakingStreamProperties.vault, 
            stakingStreamProperties.erc20, 
            weight, 
            stakingStreamProperties.streamOwner, 
            stakingScheduleTimes, 
            stakingScheduleRewards, 
            stakingProps);
    }
}