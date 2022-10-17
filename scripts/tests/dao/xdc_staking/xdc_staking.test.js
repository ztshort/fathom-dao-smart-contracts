const { web3 } = require("@openzeppelin/test-helpers/src/setup");
const BN = web3.utils.BN
const chai = require("chai");
const { expect } = chai.use(require('chai-bn')(BN));
const should = chai.use(require('chai-bn')(BN)).should();

const utils = require('../../helpers/utils');
const eventsHelper = require("../../helpers/eventsHelper");
const blockchain = require("../../helpers/blockchain");




const maxGasForTxn = 600000
const {
    shouldRevert,
    errTypes
} = require('../../helpers/expectThrow');

const SYSTEM_ACC = accounts[0];
const staker_1 = accounts[1];

const stream_owner = accounts[3];
const staker_2 = accounts[4];
const staker_3 = accounts[5];
const staker_4 = accounts[6];

const stream_manager = accounts[7];
const stream_rewarder_1 = accounts[8];
const stream_rewarder_2 = accounts[9];

let vault_test_address;
const treasury = SYSTEM_ACC;

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


const _getTimeStamp = async () => {
    const timestamp = await blockchain.getLatestBlockTimestamp()
    return timestamp
}
const _calculateNumberOfVMAINTkn = (sumToDeposit, lockingPeriod, lockingWeight) =>{
    const lockingPeriodBN = new web3.utils.BN(lockingPeriod);
    const lockingWeightBN = new web3.utils.BN(lockingWeight);
    const sumToDepositBN = new web3.utils.BN(sumToDeposit);
    
    return sumToDepositBN.mul(lockingPeriodBN).div(lockingWeightBN);
}

const _calculateNumberOfStreamShares = (sumToDeposit, veMainTokenCoefficient, nVMAINTkn, maxWeightShares) => {
    const sumToDepositBN = new web3.utils.BN(sumToDeposit);
    const veMainTokenWeightBN = new web3.utils.BN(veMainTokenCoefficient); 
    const maxWeightBN = new web3.utils.BN(maxWeightShares);
    const oneThousandBN = new web3.utils.BN(1000)
    return (sumToDepositBN.add(veMainTokenWeightBN.mul(nVMAINTkn).div(oneThousandBN))).mul(maxWeightBN);
}

const _calculateRemainingBalance = (depositAmount, beforeBalance) => {
    const depositAmountBN = new web3.utils.BN(depositAmount);
    const beforeBalanceBN = new web3.utils.BN(beforeBalance)
    return beforeBalanceBN.sub(depositAmountBN)
}

const _calculateAddition = (pendingAmount, beforeBalance) => {
    const pendingAmountBN = new web3.utils.BN(pendingAmount);
    const beforeBalanceBN = new web3.utils.BN(beforeBalance)
    return beforeBalanceBN.add(pendingAmountBN)
}

const _convertToEtherBalance = (balance) => {
    return parseFloat(web3.utils.fromWei(balance,"ether").toString()).toFixed(5)
}

describe("Staking Test", () => {

    const oneMonth = 30 * 24 * 60 * 60;
    const oneYear = 31556926;
    let stakingService;
    let vaultService;
    let WXDCToken;
    let veMainToken;

    let streamReward1;
    let streamReward2;

    let veMainTokenAddress;
    let WXDCTokenAddress;
    let streamReward1Address;
    let streamReward2Address;

    let maxWeightShares;
    let minWeightShares;
    let maxWeightPenalty;
    let minWeightPenalty;
    let veMainTokenCoefficient;
    let lockingVoteWeight;
    let totalAmountOfStakedMAINTkn;
    let totalAmountOfVMAINTkn;
    let totalAmountOfStreamShares;
    let maxNumberOfLocks;
    let _flags;
    
    const sumToDeposit = web3.utils.toWei('1', 'ether');
    const sumToTransfer = web3.utils.toWei('2000', 'ether');
    const sumToApprove = web3.utils.toWei('3000','ether');
    const sumForProposer = web3.utils.toWei('3000','ether')
    const veMainTokensToApprove = web3.utils.toWei('500000', 'ether')

    before(async() => {
        await snapshot.revertToSnapshot();
        maxWeightShares = 1024;
        minWeightShares = 256;
        maxWeightPenalty = 3000;
        minWeightPenalty = 100;
        weightMultiplier = 10;
        maxNumberOfLocks = 10;
        _flags = 0;
        

        const weightObject =  _createWeightObject(
                              maxWeightShares,
                              minWeightShares,
                              maxWeightPenalty,
                              minWeightPenalty,
                              weightMultiplier)
        //this is used for stream shares calculation.
        veMainTokenCoefficient = 500;
        //this is used for calculation of release of veMAINTkn
        lockingVoteWeight = 365 * 24 * 60 * 60;
        
        stakingService = await artifacts.initializeInterfaceAt(
            "XDCStakingHandler",
            "XDCStakingHandler"
        );

        vaultService = await artifacts.initializeInterfaceAt(
            "IVault",
            "VaultPackage"
        );


        WXDCToken = await artifacts.initializeInterfaceAt("WXDC","WXDC");
        streamReward1 = await artifacts.initializeInterfaceAt("ERC20Rewards1","ERC20Rewards1");
        streamReward2 = await artifacts.initializeInterfaceAt("ERC20Rewards2","ERC20Rewards2");
        
        await streamReward1.transfer(stream_rewarder_1,web3.utils.toWei("10000","ether"),{from: SYSTEM_ACC});
        await streamReward2.transfer(stream_rewarder_2,web3.utils.toWei("10000","ether"),{from: SYSTEM_ACC});
        
        
        
        WXDCTokenAddress = WXDCToken.address;
        streamReward1Address = streamReward1.address;
        streamReward2Address = streamReward2.address;
        
        // await WXDCToken.transfer(staker_1,sumToTransfer, {from: SYSTEM_ACC})
        // await WXDCToken.transfer(staker_2,sumToTransfer, {from: SYSTEM_ACC})
        // await WXDCToken.transfer(staker_3,sumToTransfer, {from: SYSTEM_ACC})
        // await WXDCToken.transfer(staker_4,sumToTransfer, {from: SYSTEM_ACC})
        // await WXDCToken.transfer(stream_manager, sumForProposer, {from: SYSTEM_ACC})
        

        const twentyPercentOfMAINTknTotalSupply = web3.utils.toWei('2000', 'ether');
        vault_test_address = vaultService.address;
        await WXDCToken.deposit({from: SYSTEM_ACC, value: twentyPercentOfMAINTknTotalSupply})
        await WXDCToken.transfer(vault_test_address, twentyPercentOfMAINTknTotalSupply, {from: SYSTEM_ACC})

        const startTime =  await _getTimeStamp() + 3 * 24 * 24 * 60;

        const scheduleRewards = [
            web3.utils.toWei('2000', 'ether'),
            web3.utils.toWei('1000', 'ether'),
            web3.utils.toWei('500', 'ether'),
            web3.utils.toWei('250', 'ether'),
            web3.utils.toWei("0", 'ether')
        ]
        const scheduleTimes = [
            startTime,
            startTime + oneYear,
            startTime + 2 * oneYear,
            startTime + 3 * oneYear,
            startTime + 4 * oneYear,
        ]
        await vaultService.addSupportedToken(WXDCTokenAddress)
        await vaultService.addSupportedToken(streamReward1Address)
        await vaultService.addSupportedToken(streamReward2Address)
        
        await stakingService.initializeStaking(
            vault_test_address,
            WXDCTokenAddress,            
            weightObject,
            stream_owner,
            scheduleTimes,
            scheduleRewards,
            2,
            veMainTokenCoefficient,
            lockingVoteWeight,
            maxNumberOfLocks
         )
         
    });

    
    
    describe('Creating XDC lock positions', async() => {
        it('Should Create a Lock position with native ether', async() => {
            await blockchain.increaseTime(20);
            let lockingPeriod = 24 * 60 * 60;
            const unlockTime = await _getTimeStamp() + lockingPeriod;
            const wxdcBalanceBefore = await WXDCToken.balanceOf(stakingService.address)
            let result = await stakingService.createLock(unlockTime, {value: sumToDeposit, from: staker_1});
            const wxdcTokenBalanceAfter = await WXDCToken.balanceOf(stakingService.address)
            const shouldBeBalance = _calculateAddition(wxdcBalanceBefore.toString(), wxdcTokenBalanceAfter.toString())
            assert.equal(shouldBeBalance.toString(), wxdcTokenBalanceAfter.toString())
        })

    })
});
