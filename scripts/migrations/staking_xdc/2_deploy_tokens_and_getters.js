// const ERC20TokenReward1 = artifacts.require("./registry-layer/tokens-factory/tokens/ERC-20/ERC20Token.sol");
const ERC20TokenReward1 = artifacts.require("./dao/governance/token/ERC20/ERC20Maintoken.sol");
const ERC20TokenReward2 = artifacts.require("./dao/governance/token/ERC20/ERC20Rewards1.sol");
const ERC20TokenReward3 = artifacts.require("./dao/governance/token/ERC20/ERC20Rewards2.sol");
const StakingGetters = artifacts.require('./dao/staking/helpers/StakingGettersHelper.sol')
const PackageStaking = artifacts.require('./dao/XDC_staking/XDCStakingHandler.sol');
const WXDCToken = artifacts.require('./dao/XDC_staking/tokens/WXDC.sol');



module.exports = async function(deployer) {
    let promises = [
        
        deployer.deploy(ERC20TokenReward1, "Main Token", "MTT", web3.utils.toWei("1000000","ether"), accounts[0], { gas: 3600000 }),
        deployer.deploy(ERC20TokenReward2, "Reward2 Tokens", "R2T", web3.utils.toWei("1000000","ether"), accounts[0], { gas: 3600000 }),
        deployer.deploy(ERC20TokenReward3, "Reward2 Tokens", "R3T", web3.utils.toWei("1000000","ether"), accounts[0], { gas: 3600000 }),
        deployer.deploy(StakingGetters, PackageStaking.address,{gas: 8000000}),
        deployer.deploy(WXDCToken,{ gas: 3600000 })

    ];

    await Promise.all(promises);
}