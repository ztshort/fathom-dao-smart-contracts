pragma solidity ^0.8.0;
import "@openzeppelin/contracts/proxy/Clones.sol";
import "../../XDC_staking/interfaces/IXDCStaking.sol";
import "../interfaces/IStaking.sol";
import "../vault/interfaces/IVault.sol";
import "../packages/StakingPackage.sol";
contract StakingFactory {
    event StakingCreated(address indexed owner, address indexed addr, address template);
    struct Staking {
        bool exists;
        bytes32 templateId;
    }

    bool private initialised;
    address[] public stakingAddresses;
    mapping(bytes32 => address) private FTHMStakingTemplates;
    mapping(bytes32 => address) private XDCStakingTemplates;
    mapping(address => address) private vaultAddress;
    mapping(address =>  Staking) private stakingInfo;
    address[] private stakings;

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
                bytes32 templateId, 
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
        address template = FTHMStakingTemplates[templateId];
        require(template != address(0),"staking template: addr 0");
        StakingPackage FTHMStaking = new StakingPackage();
        require(vault != address(0x00),"vault address 0");

        //TODO: Vote Token Minter role?
        //TODO: Transfer FTHM Token to vault
        //TODO: add support token FTHM Token addr
        IVault(vault).addSupportedToken(fthmToken);
        //TODO: Can make schedule times with start time
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
        address template = FTHMStakingTemplates[templateId];
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
        //TODO: Can make schedule times with start time
    }

    function addFTHMStakingTemplate(bytes32 templateId,address _template) external {
        FTHMStakingTemplates[templateId] = _template;
    }

    function addXDCStakingTemplate(bytes32 templateId,address _template) external {
        XDCStakingTemplates[templateId] = _template;
    }

    // function createStreamFTHM(){}
}