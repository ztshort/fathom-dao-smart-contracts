const StakingFactory = artifacts.require('./dao/staking/Factory/StakingFactory.sol');

module.exports = async function(deployer) {
    let promises = [
        deployer.deploy(StakingFactory, {gas: 8000000})
    ];

    await Promise.all(promises);
}