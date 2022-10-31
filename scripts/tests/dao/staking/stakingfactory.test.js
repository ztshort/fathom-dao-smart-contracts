const { web3 } = require("@openzeppelin/test-helpers/src/setup");
const BN = web3.utils.BN
const chai = require("chai");
const { expect } = chai.use(require('chai-bn')(BN));
const should = chai.use(require('chai-bn')(BN)).should();

const utils = require('../../helpers/utils');
const eventsHelper = require("../../helpers/eventsHelper");
const blockchain = require("../../helpers/blockchain");


const FTHMStakingService = artifacts.require('./dao/staking/packages/StakingPackage.sol');

const maxGasForTxn = 600000
const {
    shouldRevert,
    errTypes
} = require('../../helpers/expectThrow');

const SYSTEM_ACC = accounts[0];
const staker_1 = accounts[1];

const sumToDeposit = web3.utils.toWei('100', 'ether');
const sumToApprove = web3.utils.toWei('3000','ether');
const sumToTransfer = web3.utils.toWei('2000', 'ether');

const _createWeightObject = (
    maxWeightShares,
    minWeightShares,
    maxWeightPenalty,
    minWeightPenalty,
    weightMultiplier) => {
    return {
        maxWeightShares: maxWeightShares,
        minWeightShares: minWeightShares,
        maxWeightPenalty: maxWeightPenalty,
        minWeightPenalty: minWeightPenalty,
        penaltyWeightMultiplier: weightMultiplier
    }
}

const _createStakingProperties = (
    tau,
    lockShareCoef,
    lockPeriodCoef,
    maxLocks
) => {
    return {
        tau: tau,
        lockShareCoef: lockShareCoef,
        lockPeriodCoef: lockPeriodCoef,
        maxLocks: maxLocks
    }
}

const FTHM_STAKING = web3.utils.keccak256("FTHM_STAKING");

const _getTimeStamp = async () => {
    const timestamp = await blockchain.getLatestBlockTimestamp()
    return timestamp
}
const _calculateNumberOfVFTHM = (sumToDeposit, lockingPeriod, lockingWeight) =>{
    const lockingPeriodBN = new web3.utils.BN(lockingPeriod);
    const lockingWeightBN = new web3.utils.BN(lockingWeight);
    const sumToDepositBN = new web3.utils.BN(sumToDeposit);
    
    return sumToDepositBN.mul(lockingPeriodBN).div(lockingWeightBN);
}

const _calculateNumberOfStreamShares = (sumToDeposit, veMainTokenCoefficient, nVFTHM, maxWeightShares) => {
    const sumToDepositBN = new web3.utils.BN(sumToDeposit);
    const veMainTokenWeightBN = new web3.utils.BN(veMainTokenCoefficient); 
    const maxWeightBN = new web3.utils.BN(maxWeightShares);
    const oneThousandBN = new web3.utils.BN(1000)
    return (sumToDepositBN.add(veMainTokenWeightBN.mul(nVFTHM).div(oneThousandBN))).mul(maxWeightBN);
}

const _calculateRemainingBalance = (depositAmount, beforeBalance) => {
    const depositAmountBN = new web3.utils.BN(depositAmount);
    const beforeBalanceBN = new web3.utils.BN(beforeBalance)
    return beforeBalanceBN.sub(depositAmountBN)
}

const _calculateAfterWithdrawingBalance = (pendingAmount, beforeBalance) => {
    const pendingAmountBN = new web3.utils.BN(pendingAmount);
    const beforeBalanceBN = new web3.utils.BN(beforeBalance)
    return beforeBalanceBN.add(pendingAmountBN)
}

const _convertToEtherBalance = (balance) => {
    return parseFloat(web3.utils.fromWei(balance,"ether").toString()).toFixed(5)
}

describe("Staking Test",  () => {
    
    maxWeightShares = 1024;
    minWeightShares = 256;
    maxWeightPenalty = 3000;
    minWeightPenalty = 100;
    weightMultiplier = 10;
    maxNumberOfLocks = 10;
    _flags = 0;

    let weightObject;
    let stakingProps;
    let scheduleTimes;
    let scheduleRewards;
    let vaultService;
    let stakingService;
    let stakingFactory;
    let FTHMToken;
    let veMainToken;

    before(async() => {
        const oneYear = 31556926;
        weightObject =  _createWeightObject(
            maxWeightShares,
            minWeightShares,
            maxWeightPenalty,
            minWeightPenalty,
            weightMultiplier)
        //this is used for stream shares calculation.
        veMainTokenCoefficient = 500;
        //this is used for calculation of release of veFTHM
        lockingVoteWeight = 365 * 24 * 60 * 60;
        ///TODO:
        stakingService = await artifacts.initializeInterfaceAt(
            "IStaking",
            "StakingPackage"
        )
    
        stakingFactory = await artifacts.initializeInterfaceAt(
            "StakingFactory",
            "StakingFactory" 
        )
    
        vaultService = await artifacts.initializeInterfaceAt(
            "IVault",
            "VaultPackage"
        );
    
        stakingGetterService = await artifacts.initializeInterfaceAt(
            "StakingGettersHelper",
            "StakingGettersHelper"
        )
    
        FTHMToken = await artifacts.initializeInterfaceAt("ERC20MainToken","ERC20MainToken");
        streamReward1 = await artifacts.initializeInterfaceAt("ERC20Rewards1","ERC20Rewards1");
        streamReward2 = await artifacts.initializeInterfaceAt("ERC20Rewards2","ERC20Rewards2");
        veMainToken = await artifacts.initializeInterfaceAt("VeMainToken", "VeMainToken");
            
            
        await veMainToken.addToWhitelist(stakingService.address, {from: SYSTEM_ACC})
        
        const startTime =  await _getTimeStamp() + 3 * 24 * 24 * 60;
        await FTHMToken.transfer(staker_1,sumToTransfer, {from: SYSTEM_ACC})
        
        scheduleRewards = [
            web3.utils.toWei('200000', 'ether'),
            web3.utils.toWei('0', 'ether'),
        ]
        scheduleTimes = [
            startTime,
            startTime + oneYear,
        ]
        //this is used for stream shares calculation.
        const lockShareCoef = 500;
        //this is used for calculation of release of veFTHM
        const lockPeriodCoef = 365 * 24 * 60 * 60;
        const tau = 2
        const maxLocks = 50  
        await stakingFactory.initStakingFactory();
        await stakingFactory.addStakingTemplate(FTHM_STAKING, stakingService.address);
        stakingProps = _createStakingProperties(
            tau,
            lockShareCoef,
            lockPeriodCoef,
            maxLocks
        )
    })
    
    describe('Creating Staking with factory', async() => {
        it('Should create FTHM staking', async() => {
            //TODO: templateId, StakingProperties
            console.log("os it here???");
            
            await stakingFactory.createStakingFTHM(
                FTHM_STAKING,
                vaultService.address,
                FTHMToken.address,
                veMainToken.address,
                weightObject,
                SYSTEM_ACC,
                scheduleTimes,
                scheduleRewards,
                stakingProps
            )
            console.log("os it here???");
            let eventArgs = eventsHelper.getIndexedEventArgs(result, "StakingCreated(address,address,address)");
            minter_role = await veMainToken.MINTER_ROLE();
            await veMainToken.grantRole(minter_role, stakingService.address, {from: SYSTEM_ACC});
            
            
            let stakingAddress = eventArgs[1]
            const fthmStaking = await FTHMStakingService.at(stakingAddress);
            let lockingPeriod = 365 * 24 * 60 * 60;
            
            const unlockTime = await _getTimeStamp() + lockingPeriod;
            await FTHMToken.approve(fthmStaking.address, sumToApprove, {from: staker_1})
            result = await fthmStaking.createLock(sumToDeposit,unlockTime, {from: staker_1});
        })
    })

});