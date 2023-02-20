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
      },
    );

    const dai = await testLender.getEth();

    const loan = await testLender.getLoan(0);
    const last = await testLender.last();

    expect(dai.toString()).to.equal(daiAmount.toString());
    expect(parseInt(loan.toString())).to.be.greaterThan(0);
    expect(last.toString()).to.equal(loan.toString());

    const outstanding = await testLender.outstanding(parseInt(last.toString()));

    expect(outstanding.toString()).to.equal(
      web3.utils.toWei("30000", "ether").replace(/.$/, "1"),
    );

    const seccondAccount = accounts[1];
    await testLender.openLoanEth(
      web3.utils.stringToHex("ETH-A"),
      web3.utils.stringToHex("MCD_JOIN_ETH_A"),
      daiAmount,
      {
        from: seccondAccount,
        value: web3.utils.toWei("80", "ether"),
      },
    );

    const seccondLoan = await testLender.last();

    expect((await testLender.getLoan(0)).toString()).to.equal(last.toString());
    expect((await testLender.getLoan(1)).toString()).to.equal(
      seccondLoan.toString(),
    );

    await testLender.closeLoanEth(parseInt(last.toString()));

    expect((await testLender.getLoan(0)).toString()).to.equal(
      seccondLoan.toString(),
    );
  });
});
