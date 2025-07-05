import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import { vars } from "hardhat/config";
import "hardhat-gas-reporter";
import "solidity-coverage";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      metadata: {
        bytecodeHash: "none",      // ⬅ prevents IPFS-hash mismatch
        useLiteralContent: true,   // ⬅ embeds the full source in metadata
      },
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true // Enable via IR compilation
    }
  },
  sourcify: {
    enabled: true,
    apiUrl: "https://sourcify-api-monad.blockvision.org",
    browserUrl: "https://testnet.monadexplorer.com",
  },
  networks: {
    // Konfigurasi untuk localhost development
    hardhat: {
      chainId: 10143,
    },
    // Konfigurasi untuk Monad Testnet
    monadTestnet: {
      url: "https://testnet-rpc.monad.xyz/",
      chainId: 10143,
      accounts: vars.has("PRIVATE_KEY") ? [`0x${vars.get("PRIVATE_KEY")}`] : [],
      // gasPrice: 2000000000, // 2 gwei - start higher for congested network
      // gas: 8000000,
      // timeout: 120000, // 2 minutes timeout
      httpHeaders: {},
      // Add retry logic
      throwOnTransactionFailures: true,
      throwOnCallFailures: true,
      loggingEnabled: true,
    }
  },
  etherscan: {
    apiKey: {
      sepolia: vars.get("ETHERSCAN_API_KEY"),
    },
  },
};

export default config;