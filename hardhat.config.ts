import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  networks: {
    ropsten: {
      url: "https://ropsten.infura.io/v3/8bf322110b8c4fbf87055c7fd3981adf",
      // 'accounts': ['9164744f372f6a73c3788a5436ac0fbc58977df91b852eef53c1ef5250414b86',
      //   '33a4f333350282866d0abcf4ff407f6366a82734fafe30fdbcefbc68663d81b7']
      accounts: [
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
        "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
        "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
        "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
      ],
      gas: 8500000, // Gas sent with each transaction (default: ~6700000)
      gasLimit: 29999829,
      allowUnlimitedContractSize: true,
    },
    // kovan: {
    //   'url': 'https://kovan.infura.io/v3/8bf322110b8c4fbf87055c7fd3981adf',
    //   'accounts': ['9164744f372f6a73c3788a5436ac0fbc58977df91b852eef53c1ef5250414b86',
    //     '33a4f333350282866d0abcf4ff407f6366a82734fafe30fdbcefbc68663d81b7'],
    //   // 'accounts': ['0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
    //   //   '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
    //   //   '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a',
    //   //   '0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6']
    // }
  },
  etherscan: {
    apiKey: "XMVFM977E6W981B9QXDW7UIIDP7DTMV5VG",
  },
  mocha: {
    timeout: 100000000,
  },
};
