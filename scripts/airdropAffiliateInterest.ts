import hre from "hardhat"
import { ChainId, EIGHTEEN_ZEROES } from "./constants"
import { SS_ADDRESS } from "./deployment"
import { sleep } from "./utils/sleep"

// Airdrops affiliate interests
async function main() {
  const ethers = (hre as any).ethers
  const [admin] = await (hre as any).ethers.getSigners()
  const chainId: ChainId = await admin.getChainId()
  console.log("Admin address:", admin.address)

  const ACCOUNT = '' // Enter address to airdrop
  const DEPOSIT_SIZE = `789${EIGHTEEN_ZEROES}` // 789 USDC

  // Get contract factories
  const StableStake = await ethers.getContractFactory("StableStake")
  const StableStake = await StableStake.attach(SS_ADDRESS[chainId])

  // Airdrop
  await StableStake.airdropAffiliateInterest(ACCOUNT, DEPOSIT_SIZE)
  console.log("Airdropped affiliate interest of size", DEPOSIT_SIZE, "to", ACCOUNT)

  // Sleep
  await sleep(20000)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
