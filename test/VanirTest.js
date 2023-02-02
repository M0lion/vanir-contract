const Vanir = artifacts.require("Vanir");
const TestLender = artifacts.require("TestLender");

contract("Vanir", async (accounts) => {
  it("Open Loan gives correct dai amount", async () => {
    const vanir = await Vanir.deployed();
    const account = accounts[0];

    const testLender = await TestLender.new(vanir.address);

    const daiAmount = web3.utils.toWei("30000", "ether");

    await testLender.openLoanEth(
      web3.utils.stringToHex("ETH-A"),
      web3.utils.stringToHex("MCD_JOIN_ETH_A"),
      daiAmount,
      {
        from: account,
        value: web3.utils.toWei("80", "ether"),
      }
    );

    const dai = await testLender.getEth();

    console.log(JSON.stringify(dai));
    expect(dai.toString()).to.equal(daiAmount.toString());
  });
});
