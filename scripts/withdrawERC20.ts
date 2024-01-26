import hre from "hardhat"
import { ChainId, EIGHTEEN_ZEROES, SIX_ZEROES, SUPPORTED_TOKEN_ADDRESS } from "./constants"
import { SS_ADDRESS } from "./deployment"
import { sleep } from "./utils/sleep"

// Withdraws liquidity from the contract (to add liquidity, simply send USDC to the contract's address)
async function main() {
  const ethers = (hre as any).ethers
  const [admin] = await (hre as any).ethers.getSigners()
  const chainId: ChainId = await admin.getChainId()
  console.log("Admin address:", admin.address)

  const TOKEN_ADDRESS = SUPPORTED_TOKEN_ADDRESS[chainId]
  const QUANTITY = `123${EIGHTEEN_ZEROES}`
  
  // Get contract factories
  const StableStake = await ethers.getContractFactory("StableStake")
  const stableStake = await StableStake.attach(SS_ADDRESS[chainId])

  // Withdraw
  await stableStake.withdrawERC20(TOKEN_ADDRESS, QUANTITY)
  console.log("Withdrew", QUANTITY, "tokens from StableStake contract")

  // Sleep
  await sleep(20000)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
