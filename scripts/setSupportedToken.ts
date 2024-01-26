import hre from "hardhat"
import { ChainId, EIGHTEEN_ZEROES, SUPPORTED_TOKEN_ADDRESS } from "./constants"
import { SS_ADDRESS } from "./deployment"
import { sleep } from "./utils/sleep"

// Updates supported token - in case something's wrong with supported token in the future (depeg, blacklist, liquidity...)
async function main() {
  const ethers = (hre as any).ethers
  const [admin] = await (hre as any).ethers.getSigners()
  const chainId: ChainId = await admin.getChainId()
  console.log("Admin address:", admin.address)

  const NEW_TOKEN_ADDRESS = SUPPORTED_TOKEN_ADDRESS[chainId]

  // Get contract factories
  const StableStake = await ethers.getContractFactory("StableStake")
  const stableStake = await StableStake.attach(SS_ADDRESS[chainId])

  // Set supported token
  await stableStake.setSupportedToken(NEW_TOKEN_ADDRESS)
  console.log("Set supportedToken to", NEW_TOKEN_ADDRESS)

  // Sleep
  await sleep(20000)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
