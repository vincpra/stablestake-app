import hre from "hardhat"
import { ChainId } from "./constants"
import { SS_ADDRESS } from "./deployment"
import { sleep } from "./utils/sleep"

// Cash out all deposits for account 1 (testnet)
async function main() {
  const ethers = (hre as any).ethers
  const [admin] = await (hre as any).ethers.getSigners()
  const chainId: ChainId = await admin.getChainId()
  console.log("Admin address:", admin.address)

  // Get contract factories
  const StableStake = await ethers.getContractFactory("StableStake")
  const StableStake = await StableStake.attach(SS_ADDRESS[chainId])

  // Cashout all deposits
  await StableStake.cashoutAllDeposits()
  console.log("Cashed out all admin deposits")

  // Sleep
  await sleep(20000)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
