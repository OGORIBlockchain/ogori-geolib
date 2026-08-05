require("@nomicfoundation/hardhat-ethers");
module.exports = {
  solidity: { version: "0.8.19", settings: { optimizer: { enabled: true, runs: 200 }, evmVersion: "paris" } },
  networks: { hardhat: { blockGasLimit: 30000000 } }
};
