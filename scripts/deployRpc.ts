import { ethers } from "hardhat";

async function main() {
  const Vanir = await ethers.getContractFactory("Vanir");
  const vanir = await Vanir.deploy(
    "0x6B175474E89094C44Da98b954EedeAC495271d0F"
  );
  await vanir.deployed();

  console.log("Vanir deployed to:", vanir.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
