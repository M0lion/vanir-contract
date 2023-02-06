require("dotenv").config();

const ethers = require("ethers");
const { TransactionTypes } = require("ethers/lib/utils");
const FireblocksDefi = require("fireblocks-defi-sdk");
const fs = require("fs");

const apiKey = fs.readFileSync("fireblocks_secret.key", "utf-8");

const fireblocksClient = new FireblocksDefi.FireblocksSDK(
  apiKey,
  "84739ff5-c512-5a08-931e-72247181c2e3",
  "https://api.fireblocks.io"
);

const bridge = new FireblocksDefi.EthersBridge({
  vaultAccountId: "3",
  fireblocksApiClient: fireblocksClient,
  chain: FireblocksDefi.Chain.GOERLI,
});


//Create deploy transcation
const contract = require("./build/contracts/Vanir.json");

const factory = new ethers.ContractFactory(contract.abi, contract.bytecode);

const transcation = factory.getDeployTransaction("0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F");

transcation.to = "0x0";

bridge.sendTransaction(transcation);
