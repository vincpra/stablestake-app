import hre from "hardhat"
import { ChainId, EIGHTEEN_ZEROES, SUPPORTED_TOKEN_ADDRESS } from "./constants"
import { SS_ADDRESS } from "./deployment"
import { sleep } from "./utils/sleep"

// Forbids users (including users who have already deposited funds) to create deposits or cashout
// Use appropriate commented out function with true or false
async function main() {
  const ethers = (hre as any).ethers
  const [admin] = await (hre as any).ethers.getSigners()
  const chainId: ChainId = await admin.getChainId()
  console.log("Admin address:", admin.address)
  
  // Get contract factories
  const StableStake = await ethers.getContractFactory("StableStake")
  const StableStake = await StableStake.attach(SS_ADDRESS[chainId])
  
  // Note: Choose relevant function & bool + console.log
  // await StableStake.pauseDepositCreation(true)
  // await StableStake.pauseDepositCreation(false)
  await StableStake.pauseCashout(true)
  // await StableStake.pauseCashout(false)
  // console.log("Paused deposit creation")
  // console.log("Resumed deposit creation")
  console.log("Paused cashout")
  // console.log("Resumed cashout")

  // Sleep
  await sleep(20000)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
