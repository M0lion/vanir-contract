// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../contracts/Vanir.sol";

contract TestLender {
  Vanir vanir;

  constructor(address vanirAddress) {
    vanir = Vanir(vanirAddress);
  }

  function openLoanEth(bytes32 ilkKey, bytes32 joinKey, uint daiAmount) payable public {
    vanir.openLoanETH{value:msg.value}(ilkKey, joinKey, address(this), daiAmount);

  }

  function getEth() public view returns (uint256) {
    DaiToken daiToken = DaiToken(vanir.mcdAddressProvider().getAddress("MCD_DAI"));

    return daiToken.balanceOf(address(this));
  }
}