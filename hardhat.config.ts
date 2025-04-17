import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ignition";
import { ethers } from "ethers";

import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 31337,
      accounts: {
        count: 1001,  // 1000 players + 1 owner
        accountsBalance: ethers.parseEther("100000").toString(),  // Increased to 100,000 ETH
      },
      blockGasLimit: 4000000000000 
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337
    },
    blaze: {
      url: "https://sonic-blaze.g.alchemy.com/v2/GdeOJcP1A5nVB4VsMm4KN0wDVA2yy6iL",
      accounts: [process.env.DEV_PRIVATE_KEY || ""]
    },
    sonic: {
      url: "https://sonic-mainnet.g.alchemy.com/v2/GdeOJcP1A5nVB4VsMm4KN0wDVA2yy6iL",
      accounts: [process.env.DEV_PRIVATE_KEY || ""]
    }
  },

  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true
    }
  },
 
  
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  }
};

export default config;
