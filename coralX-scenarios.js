module.exports = {
  deployMainnet: [
    ['execute', '--path', 'scripts/migrations/compliance-upgradability', '--network', 'mainnet'],
    ['execute', '--path', 'scripts/migrations/tokens-creation-service', '--network', 'mainnet'],
    ['execute', '--path', 'scripts/configurations/1_base_config.js', '--network', 'mainnet'],
    ['execute', '--path', 'scripts/configurations/2_tokens_factory.js', '--network', 'mainnet'],
    ['execute', '--path', 'scripts/custom/white-list-setup.js', '--network', 'mainnet'],
  ],
  deployKovan: [
    ['execute', '--path', 'scripts/migrations/compliance-upgradability', '--network', 'kovan'],
    ['execute', '--path', 'scripts/migrations/tokens-creation-service', '--network', 'kovan'],
    ['execute', '--path', 'scripts/configurations/1_base_config.js', '--network', 'kovan'],
    ['execute', '--path', 'scripts/configurations/2_tokens_factory.js', '--network', 'kovan'],
    ['execute', '--path', 'scripts/custom/white-list-setup.js', '--network', 'kovan'],
  ],
  deployRopsten: [
    ['execute', '--path', 'scripts/migrations/compliance-upgradability', '--network', 'ropsten'],
    ['execute', '--path', 'scripts/migrations/tokens-creation-service', '--network', 'ropsten'],
    ['execute', '--path', 'scripts/configurations/1_base_config.js', '--network', 'ropsten'],
    ['execute', '--path', 'scripts/configurations/2_tokens_factory.js', '--network', 'ropsten'],
    ['execute', '--path', 'scripts/custom/white-list-setup.js', '--network', 'ropsten'],
  ],
  deployACMainnet: [
    ['execute', '--path', 'scripts/migrations/compliance-upgradability', '--network', 'mainnet'],
    ['execute', '--path', 'scripts/migrations/tokens-creation-service', '--network', 'mainnet'],
    ['execute', '--path', 'scripts/migrations/composer', '--network', 'mainnet'],
    ['execute', '--path', 'scripts/configurations/1_base_config.js', '--network', 'mainnet'],
    ['execute', '--path', 'scripts/configurations/2_tokens_factory.js', '--network', 'mainnet'],
    ['execute', '--path', 'scripts/configurations/3_composer.js', '--network', 'mainnet'],
    ['execute', '--path', 'scripts/custom/white-list-setup.js', '--network', 'mainnet'],
  ],
  deployACKovan: [
    ['execute', '--path', 'scripts/migrations/compliance-upgradability', '--network', 'kovan'],
    ['execute', '--path', 'scripts/migrations/tokens-creation-service', '--network', 'kovan'],
    ['execute', '--path', 'scripts/migrations/composer', '--network', 'kovan'],
    ['execute', '--path', 'scripts/configurations/1_base_config.js', '--network', 'kovan'],
    ['execute', '--path', 'scripts/configurations/2_tokens_factory.js', '--network', 'kovan'],
    ['execute', '--path', 'scripts/configurations/3_composer.js', '--network', 'kovan'],
    ['execute', '--path', 'scripts/custom/white-list-setup.js', '--network', 'kovan'],
  ],
  deployACRopsten: [
    ['execute', '--path', 'scripts/migrations/compliance-upgradability', '--network', 'ropsten'],
    ['execute', '--path', 'scripts/migrations/tokens-creation-service', '--network', 'ropsten'],
    ['execute', '--path', 'scripts/migrations/composer', '--network', 'ropsten'],
    ['execute', '--path', 'scripts/configurations/1_base_config.js', '--network', 'ropsten'],
    ['execute', '--path', 'scripts/configurations/2_tokens_factory.js', '--network', 'ropsten'],
    ['execute', '--path', 'scripts/configurations/3_composer.js', '--network', 'ropsten'],
    ['execute', '--path', 'scripts/custom/white-list-setup.js', '--network', 'ropsten'],
  ],

  deployDAOGoerli: [
    ['execute', '--path', 'scripts/migrations/governance', '--network', 'goerli'],
  ],

  

  migrateAndConfigureForTests: [
    ['compile'],
    ['execute', '--path', 'scripts/migrations/governance'],
  ],
}
