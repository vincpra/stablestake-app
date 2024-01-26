import hre from "hardhat"
import { ChainId } from "./constants"
import { SS_ADDRESS } from "./deployment"
import { sleep } from "./utils/sleep"

// Updates investment and fees wallets - make sure said wallets own a bit of untrackable BNB in order to send transactions, as all they will receive from users is USDC
async function main() {
  const ethers = (hre as any).ethers
  const [admin] = await (hre as any).ethers.getSigners()
  const chainId: ChainId = await admin.getChainId()
  console.log("Admin address:", admin.address)

  // Get contract factories
  const StableStake = await ethers.getContractFactory("StableStake")
  const stableStake = await StableStake.attach(SS_ADDRESS[chainId])

  // Set investment wallet
  await stableStake.setInvestmentWallet("0x")
  console.log("Updated investment wallet")

  // Sleep
  await sleep(10000)

  // Set fees wallet
  await stableStake.setFeesWallet("0x")
  console.log("Updated fees wallet")

  // Sleep
  await sleep(20000)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
