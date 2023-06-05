import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: "0.8.20",
  networks: {
    hardhat: {
      forking: {
        url: "https://eth-mainnet.g.alchemy.com/v2/n40fvsyFIAYsF3hKHTUMcDFvGQe80Czp",
        blockNumber: 17392083,
      },
    },
    devnet: {
      url: "https://rpc.vnet.tenderly.co/devnet/vanir-test/5ea3d88a-2c4b-424d-aaed-5b0ba959f230",
      chainId: 1,
    },
  },
};

export default config;
