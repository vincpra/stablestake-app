import hre from "hardhat"
import { ChainId, EIGHTEEN_ZEROES, SUPPORTED_TOKEN_ADDRESS } from "./constants"
import { SS_ADDRESS } from "./deployment"
import { sleep } from "./utils/sleep"

// Updates first deposit (index 0) of an user: size, last claim time...
async function main() {
  const ethers = (hre as any).ethers
  const [admin] = await (hre as any).ethers.getSigners()
  const chainId: ChainId = await admin.getChainId()
  console.log("Admin address:", admin.address)

  const ADDRESS = ""
  const INDEX = "0"
  const NEW_SIZE = `123${EIGHTEEN_ZEROES}` // 123 USDC

  // Get contract factories
  const StableStake = await ethers.getContractFactory("StableStake")
  const stableStake = await StableStake.attach(SS_ADDRESS[chainId])

  await stableStake.updateDepositSize(ADDRESS, INDEX, NEW_SIZE)
  console.log("Updated deposit", INDEX, "of address", ADDRESS, "to a size of", NEW_SIZE)

  // Sleep
  await sleep(20000)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
