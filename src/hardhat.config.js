require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-ethers");
// Run abi exporter
require("hardhat-abi-exporter");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.9",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000,
          },
        },
      },
    ],
  },
  abiExporter: [
    {
      path: './abi/json',
      format: "json",
    }
  ],
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true
    },
    localhost: {
      allowUnlimitedContractSize: true
    }
  },
};
