import hre from "hardhat"
import { ChainId, DEX_ROUTER } from "./constants"
import { sleep } from "./utils/sleep"

// Supported token replacing USDC. Only used for testnet
async function main() {
  const ethers = (hre as any).ethers
  const [admin] = await (hre as any).ethers.getSigners()
  const chainId: ChainId = await admin.getChainId()
  console.log("Admin address:", admin.address)

  // Get contract factories
  const TOKEN = await ethers.getContractFactory("TOKEN")

  // Deploy TOKEN
  const token = await TOKEN.deploy(DEX_ROUTER[chainId], admin.address)
  await token.deployed()
  console.log("TOKEN deployed to:", token.address)

  await sleep(60000)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
