import { ethers } from "hardhat";
import walletInfo from "../wallet.json";

const provider = new ethers.providers.AlchemyProvider(
  "goerli",
  "n40fvsyFIAYsF3hKHTUMcDFvGQe80Czp"
);

const wallet = new ethers.Wallet(walletInfo.privateKey, provider);

const addressProvider = "0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F";
async function main() {
  const Vanir = await ethers.getContractFactory("Vanir", wallet);
  const vanir = await Vanir.deploy(addressProvider);
  await vanir.deployed();

  console.log("Vanir deployed to:", vanir.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
