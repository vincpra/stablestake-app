import "@typechain/hardhat"
import "@nomiclabs/hardhat-ethers"
import "@nomiclabs/hardhat-waffle"
import "hardhat-contract-sizer"
import fs from "fs"
// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const mnemonic = fs.existsSync("../mnemonic.txt") ? fs.readFileSync("../mnemonic.txt", "utf-8").trim() : ""
if (!mnemonic) console.log("Missing mnemonic")

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    bscMainnet: {
      url: "https://bsc-dataseed1.binance.org",
      chainId: 56,
      accounts: {
        mnemonic
      }
    },
    bscTestnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      chainId: 97,
      accounts: {
        mnemonic
      }
    }
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
    alwaysGenerateOverloads: false, // should overloads with full signatures like deposit(uint256) be generated always, even if there are no overloads?
    externalArtifacts: ["externalArtifacts/*.json"] // optional array of glob patterns with external artifacts to process (for example external libs from node_modules)
  }
}
