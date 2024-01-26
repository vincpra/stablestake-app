import hre from "hardhat"
import { ChainId, EIGHTEEN_ZEROES } from "./constants"
import { SS_ADDRESS } from "./deployment"
import { sleep } from "./utils/sleep"

// Sets mini deposit size for deposit type 0, as well as global maximum first & maximum deposit size
async function main() {
  const ethers = (hre as any).ethers
  const [admin] = await (hre as any).ethers.getSigners()
  const chainId: ChainId = await admin.getChainId()
  console.log("Admin address:", admin.address)

  const NEW_MIN_DEPOSIT = `100${EIGHTEEN_ZEROES}` // 100 USDC

  // Parameters:
  // uint256 _depositType,
  // uint256 _lockPeriod,
  // uint256 _minimalDeposit,
  // uint256 _multiplier,
  // uint256 _rewardInterval

  // Get contract factories
  const StableStake = await ethers.getContractFactory("StableStake")
  const stableStake = await StableStake.attach(SS_ADDRESS[chainId])

  // Note: This is for deposit type 0 (default)
  await stableStake.updateDepositType(0, 60, NEW_MIN_DEPOSIT, 100, 60) // No lock - 20% - 1000 seconds reward interval
  // await stableStake.updateDepositType(0, 2_592_000, NEW_MIN_DEPOSIT, 100, 2_592_000) // No lock - 20% - 1000 seconds reward interval
  console.log("Set minimum deposit to", NEW_MIN_DEPOSIT)

  // Sleep
  await sleep(20000)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
