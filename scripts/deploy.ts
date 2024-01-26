import hre from "hardhat"
import { ChainId, FEES_WALLET, INVESTMENT_WALLET, SUPPORTED_TOKEN_ADDRESS } from "./constants"
import { sleep } from "./utils/sleep"

// MAINNET values
// 7776000 _initialVestingPeriodOfAffiliateInterests
// 2592000 _initialInterval

// TESTNET values
// 180 _initialVestingPeriodOfAffiliateInterests
// 60 _initialInterval

// Deploys a new version of StableStake - note: save the deployed contract's address in deployment.ts
async function main() {
  const ethers = (hre as any).ethers
  const [admin] = await (hre as any).ethers.getSigners()
  const chainId: ChainId = await admin.getChainId()
  console.log("Admin address:", admin.address)

  // Get contract factories
  const StableStake = await ethers.getContractFactory("StableStake")

  // Deploy StableStake
  // const StableStake = await StableStake.deploy(FEES_WALLET, INVESTMENT_WALLET, SUPPORTED_TOKEN_ADDRESS[chainId], 60, 180)
  const StableStake = await StableStake.deploy(FEES_WALLET, INVESTMENT_WALLET, SUPPORTED_TOKEN_ADDRESS[chainId], 2592000, 7776000)
  await StableStake.deployed()
  console.log("StableStake deployed to:", StableStake.address)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
