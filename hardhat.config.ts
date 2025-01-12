import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
const { vars } = require("hardhat/config");

const FEE_DEVELOPER_KEY = vars.get("SEPOLIA_PRIVATE_KEY");

const config: HardhatUserConfig = {
  solidity: "0.8.27",
  networks: {
    worldchain: {
      url: `0x7241a0f2577c4a53adB35491c2cb471Aa5041557`,
      accounts: [FEE_DEVELOPER_KEY],
    },
  },
};

export default config;
