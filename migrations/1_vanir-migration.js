const Vanir = artifacts.require("Vanir");

module.exports = function (deployer, network) {
  if (network === "development") {
    deployer.deploy(Vanir, "0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F");
  } else {
    throw "Unconfigured network";
  }
};
