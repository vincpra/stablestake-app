import hre from "hardhat"
import { ChainId } from "./constants"
import { SS_ADDRESS } from "./deployment"
import { sleep } from "./utils/sleep"

// Changes proportions between user funds sent to investmentWallet and feesWallet
async function main() {
  const ethers = (hre as any).ethers
  const [admin] = await (hre as any).ethers.getSigners()
  const chainId: ChainId = await admin.getChainId()
  console.log("Admin address:", admin.address)

  const NEW_FEE = '0' // (/1000)

  // Get contract factories
  const StableStake = await ethers.getContractFactory("StableStake")
  const stableStake = await StableStake.attach(SS_ADDRESS[chainId])

  await stableStake.setCreateDepositFee(NEW_FEE)
  console.log("Set createDepositFee to", NEW_FEE)

  // Sleep
  await sleep(20000)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
