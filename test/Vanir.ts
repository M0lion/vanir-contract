import { expect } from "chai";
import { BigNumber, Signer } from "ethers";
import { config, ethers } from "hardhat";
import { Vanir } from "../typechain-types/Vanir";
import { DaiToken } from "../typechain-types/Interfaces.sol/DaiToken";
import { time } from "@nomicfoundation/hardhat-network-helpers";

const DAI_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

function getDaiContract(signer: Signer) {
  return ethers.getContractAt("DaiToken", DAI_ADDRESS, signer);
}

function getJugContract(signer: Signer) {
  return ethers.getContractAt(
    "McdJug",
    "0x19c0976f590D67707E62397C87829d896Dc0f1F1",
    signer
  );
}

function getVatContract(signer: Signer) {
  return ethers.getContractAt(
    "McdVat",
    "0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B",
    signer
  );
}

function getMcdManagerContract(signer: Signer) {
  return ethers.getContractAt(
    "McdCdpManager",
    "0x5ef30b9986345249bc32d8928B7ee64DE9435E39",
    signer
  );
}

describe("Vanir", function () {
  async function deployVanirFixture() {
    const [owner] = await ethers.getSigners();

    const Vanir = await ethers.getContractFactory("Vanir");
    const vanir = await Vanir.deploy(
      "0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F"
    );
    await vanir.deployed();
    return { vanir, owner };
  }

  async function deployVanirWithLoanFixture() {
    const { vanir, owner } = await deployVanirFixture();

    const loanAmount = 4500;
    const collateralAmount = 16;

    const cdp = await openLoan(loanAmount, collateralAmount, vanir);

    return { vanir, owner, cdp, loanAmount, collateralAmount };
  }

  describe("open", function () {
    it("should open a position", async function () {
      const { vanir, owner } = await deployVanirFixture();
      const daiContract = await getDaiContract(owner);

      console.log("owner.address", owner.address);

      const originalDaiBalance = await daiContract.balanceOf(owner.address);
      console.log("originalDaiBalance", originalDaiBalance.toString());

      const loanAmount = 3500;
      const collateralAmount = 4;

      const cdp = openLoan(loanAmount, collateralAmount, vanir);

      const debt = await vanir.debt(owner.address, cdp);

      expect(debt, "Debt").to.equal(
        ethers.utils.parseUnits(loanAmount.toString(), await vanir.decimals())
      );

      const daiBalance = await daiContract.balanceOf(owner.address);
      expect(daiBalance, "Dai balance").to.equal(
        ethers.utils
          .parseUnits(loanAmount.toString(), await daiContract.decimals())
          .add(originalDaiBalance)
      );
    });
  });

  describe("close", function () {
    it("should close a position", async function () {
      const { vanir, owner, cdp, loanAmount, collateralAmount } =
        await deployVanirWithLoanFixture();
      const daiContract = await getDaiContract(owner);
      const jug = await getJugContract(owner);
      let gasSpent = BigNumber.from(0);

      const originalDaiBalance = await daiContract.balanceOf(owner.address);
      const originalEtherBalance = await owner.getBalance();

      await time.increase(60 * 60 * 24 * 5);

      const dripTx = await jug.drip(ethers.utils.formatBytes32String("ETH-C"));
      const dripReceipt = await dripTx.wait();
      gasSpent = gasSpent.add(
        dripReceipt.gasUsed.mul(dripReceipt.effectiveGasPrice)
      );

      const totalDebt = await vanir.debt(owner.address, cdp);
      const approveTx = await daiContract.approve(vanir.address, totalDebt);
      const approveReceipt = await approveTx.wait();
      gasSpent = gasSpent.add(
        approveReceipt.gasUsed.mul(approveReceipt.effectiveGasPrice)
      );

      const tx = await vanir.close(owner.address, cdp);
      const receipt = await tx.wait();
      gasSpent = gasSpent.add(receipt.gasUsed.mul(receipt.effectiveGasPrice));

      const daiBalance = await daiContract.balanceOf(owner.address);
      expect(daiBalance, "Dai balance").to.equal(
        originalDaiBalance.sub(totalDebt)
      );

      await expect(vanir.debt(owner.address, cdp)).to.be.revertedWith(
        "Vanir/loan does not exist"
      );

      const etherBalance = await owner.getBalance();
      expect(etherBalance, "Ether balance").to.equal(
        originalEtherBalance
          .sub(gasSpent)
          .add(ethers.utils.parseEther(collateralAmount.toString()))
      );
    });
  });

  describe("frob", function () {
    it("adds collateral", async function () {
      const { vanir, owner, cdp } = await deployVanirWithLoanFixture();
      const vat = await getVatContract(owner);
      const mcdManager = await getMcdManagerContract(owner);

      const { ink: originalCollateral } = await vanir.loans(owner.address, cdp);
      const originalEtherBalance = await owner.getBalance();

      const rawCollateralToAdd = "1";
      const collateralToAdd = ethers.utils.parseUnits(
        rawCollateralToAdd,
        await vanir.decimals()
      );

      await vanir.frob(owner.address, cdp, collateralToAdd, 0, {
        value: ethers.utils.parseEther(rawCollateralToAdd),
      });

      const urn = await mcdManager.urns(cdp);
      const { ink: collateralFromVat } = await vat.urns(
        ethers.utils.formatBytes32String("ETH-C"),
        urn
      );
      expect(collateralFromVat, "Vat's collateral").to.equal(
        originalCollateral.add(collateralToAdd)
      );

      const { ink: collateralFromVanir } = await vanir.loans(
        owner.address,
        cdp
      );
      expect(collateralFromVanir, "Vanir's collateral").to.equal(
        originalCollateral.add(collateralToAdd)
      );

      const etherBalance = await owner.getBalance();
      expect(etherBalance, "Ether balance to be lesser").to.be.lessThan(
        originalEtherBalance
      );
    });

    it("removes collateral", async function () {
      const { vanir, owner, cdp } = await deployVanirWithLoanFixture();
      const vat = await getVatContract(owner);
      const mcdManager = await getMcdManagerContract(owner);

      const { ink: originalCollateral } = await vanir.loans(owner.address, cdp);
      const originalEtherBalance = await owner.getBalance();
      let gasSpent = BigNumber.from(0);

      const rawCollateralToRemove = "-10";
      const collateralToRemove = ethers.utils.parseUnits(
        rawCollateralToRemove,
        await vanir.decimals()
      );

      const frobTx = await vanir.frob(
        owner.address,
        cdp,
        collateralToRemove,
        0
      );
      const frobReceipt = await frobTx.wait();
      gasSpent = gasSpent.add(
        frobReceipt.gasUsed.mul(frobReceipt.effectiveGasPrice)
      );

      const expectedCollateral = originalCollateral.add(collateralToRemove);

      const urn = await mcdManager.urns(cdp);
      const { ink: collateralFromVat } = await vat.urns(
        ethers.utils.formatBytes32String("ETH-C"),
        urn
      );
      expect(collateralFromVat, "Vat's collateral").to.equal(
        expectedCollateral
      );

      const { ink: collateralFromVanir } = await vanir.loans(
        owner.address,
        cdp
      );
      expect(collateralFromVanir, "Vanir's collateral").to.equal(
        expectedCollateral
      );

      const etherBalance = await owner.getBalance();
      expect(etherBalance, "Ether balance to be greater").to.equal(
        originalEtherBalance.sub(gasSpent)
      );
    });

    it("adds debt", async function () {
      const { vanir, owner, cdp } = await deployVanirWithLoanFixture();
      const daiContract = await getDaiContract(owner);
      const vat = await getVatContract(owner);
      const mcdManager = await getMcdManagerContract(owner);

      const originalDaiBalance = await daiContract.balanceOf(owner.address);

      const rawDebtToAdd = "500";
      const debtToAdd = ethers.utils.parseUnits(
        rawDebtToAdd,
        await vanir.decimals()
      );

      await vanir.frob(owner.address, cdp, 0, debtToAdd);

      const urn = await mcdManager.urns(cdp);
      const { art: debtFromVat } = await vat.urns(
        ethers.utils.formatBytes32String("ETH-C"),
        urn
      );
      const { art: debtFromVanir } = await vanir.loans(owner.address, cdp);
      expect(debtFromVanir, "same debt").to.equal(debtFromVat);

      const daiBalance = await daiContract.balanceOf(owner.address);
      expect(daiBalance, "Dai balance").to.equal(
        originalDaiBalance.add(debtToAdd)
      );
    });

    it("removes debt", async function () {
      const { vanir, owner, cdp } = await deployVanirWithLoanFixture();
      const daiContract = await getDaiContract(owner);
      const vat = await getVatContract(owner);
      const mcdManager = await getMcdManagerContract(owner);

      const originalDaiBalance = await daiContract.balanceOf(owner.address);

      const rawDebtToRemove = "-500";
      const debtToRemove = ethers.utils.parseUnits(
        rawDebtToRemove,
        await vanir.decimals()
      );

      await daiContract.approve(
        vanir.address,
        ethers.utils
          .parseUnits(rawDebtToRemove, await daiContract.decimals())
          .mul(-1)
      );

      await vanir.frob(owner.address, cdp, 0, debtToRemove);

      const urn = await mcdManager.urns(cdp);
      const { art: debtFromVat } = await vat.urns(
        ethers.utils.formatBytes32String("ETH-C"),
        urn
      );
      const { art: debtFromVanir } = await vanir.loans(owner.address, cdp);
      expect(debtFromVanir, "same debt").to.equal(debtFromVat);

      const daiBalance = await daiContract.balanceOf(owner.address);
      expect(daiBalance, "Dai balance").to.equal(
        originalDaiBalance.add(debtToRemove)
      );
    });
  });
});

async function openLoan(loanAmount: number, collateral: number, vanir: Vanir) {
  await vanir.open(
    ethers.utils.formatBytes32String("ETH-C"),
    ethers.utils.formatBytes32String("MCD_JOIN_ETH_C"),
    ethers.utils.parseUnits(loanAmount.toString(), await vanir.decimals()),
    {
      value: ethers.utils.parseEther(collateral.toString()),
    }
  );

  const cdp = await vanir.last(vanir.signer.getAddress());

  return cdp;
}

async function approve(target: string, amount: number, daiContract: DaiToken) {
  await daiContract.approve(
    target,
    ethers.utils.parseUnits(amount.toString(), await daiContract.decimals())
  );
}
