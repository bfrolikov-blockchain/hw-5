import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const CHAIN_IDS = {
  hardhat: 31337, // chain ID for hardhat testing
};

const config: HardhatUserConfig = {
  solidity: "0.8.17",
  networks: {
    hardhat: {
      chainId: CHAIN_IDS.hardhat,
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
        blockNumber: 12821000,
      }
    }
  }
};

export default config;
