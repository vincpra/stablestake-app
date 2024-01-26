import hre from "hardhat"
import { ChainId, EIGHTEEN_ZEROES, SUPPORTED_TOKEN_ADDRESS } from "./constants"
import { SS_ADDRESS } from "./deployment"
import { sleep } from "./utils/sleep"

const ADDRESS = "0x" // Enter address to blacklist

// Logs deposited value and available interest for a given account
async function main() {
  const ethers = (hre as any).ethers
  const [admin] = await (hre as any).ethers.getSigners()
  const chainId: ChainId = await admin.getChainId()
  console.log("Admin address:", admin.address)

  // Get contract factories
  const StableStake = await ethers.getContractFactory("StableStake")
  const StableStake = await StableStake.attach(SS_ADDRESS[chainId])

  try {
    console.log(
      "Last Claim Times As Array:",
      (await StableStake.getAccountLastClaimTimes(ADDRESS))
      // "Next Interest Times As Array:",
      // (await StableStake.getAccountNextInterestTimes(ADDRESS))
    )
  } catch (error) {
    console.error("An unexpected error occurred:", error)
  }
  // Sleep
  await sleep(20000)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
