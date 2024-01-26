import hre from "hardhat"
import { ChainId, EIGHTEEN_ZEROES } from "./constants"
import { SS_ADDRESS } from "./deployment"
import { sleep } from "./utils/sleep"

// Airdrops a deposit
async function main() {
  const ethers = (hre as any).ethers
  const [admin] = await (hre as any).ethers.getSigners()
  const chainId: ChainId = await admin.getChainId()
  console.log("Admin address:", admin.address)

  const ACCOUNT = '0x' // Enter address to airdrop
  const DEPOSIT_SIZE = `1234${EIGHTEEN_ZEROES}` // 1,234 USDC

  // Get contract factories
  const StableStake = await ethers.getContractFactory("StableStake")
  const StableStake = await StableStake.attach(SS_ADDRESS[chainId])

  // Airdrop a deposit of type 0
  await StableStake.airdropDeposit(ACCOUNT, 0, DEPOSIT_SIZE)
  console.log("Airdropped deposit of size", DEPOSIT_SIZE, "to", ACCOUNT)

  // Sleep
  await sleep(10000)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
