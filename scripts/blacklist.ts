import hre from "hardhat"
import { ChainId, EIGHTEEN_ZEROES, SUPPORTED_TOKEN_ADDRESS } from "./constants"
import { SS_ADDRESS } from "./deployment"
import { sleep } from "./utils/sleep"

const ADDRESS = '0x' // Enter address to blacklist

// Blacklists an address - prevents user from depositing or claiming
async function main() {
  const ethers = (hre as any).ethers
  const [admin] = await (hre as any).ethers.getSigners()
  const chainId: ChainId = await admin.getChainId()
  console.log("Admin address:", admin.address)

  // Get contract factories
  const StableStake = await ethers.getContractFactory("StableStake")
  const StableStake = await StableStake.attach(SS_ADDRESS[chainId])

  // Note: Choose relevant address & bool
  await StableStake.blacklist(ADDRESS, true)
  console.log("Blacklisted address", ADDRESS)

  // Sleep
  await sleep(20000)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
