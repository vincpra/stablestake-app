import hre from "hardhat";
import { ChainId, EIGHTEEN_ZEROES, SUPPORTED_TOKEN_ADDRESS } from "./constants";
import { SS_ADDRESS } from "./deployment";
import { sleep } from "./utils/sleep";

const ADDRESS = ""; // Enter address to blacklist

// Logs deposited value and available interest for a given account
async function main() {
  const ethers = (hre as any).ethers;
  const [admin] = await (hre as any).ethers.getSigners();
  const chainId: ChainId = await admin.getChainId();
  console.log("Admin address:", admin.address);

  // Get contract factories
  const StableStake = await ethers.getContractFactory("StableStake");
  const StableStake = await StableStake.attach(SS_ADDRESS[chainId]);

  try {
    console.log(
      ADDRESS,
      "Deposited value:",
      (await StableStake.getAccountDepositedValue(ADDRESS)) / 10 ** 18,
      "USDC"
    );
    console.log(
      ADDRESS,
      "Account Interest Available:",
      (await StableStake.getAccountInterestAvailable(ADDRESS)) / 10 ** 18,
      "USDC"
    );
  } catch (error) {
    console.error("An unexpected error occurred:", error);
  }
  // Sleep
  await sleep(20000);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
