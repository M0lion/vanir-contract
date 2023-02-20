// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../contracts/Vanir.sol";

contract TestLender {
  Vanir vanir;

  constructor(address payable vanirAddress) {
    vanir = Vanir(vanirAddress);
  }

  function openLoanEth(bytes32 ilkKey, bytes32 joinKey, uint daiAmount) payable public {
    vanir.openLoanETH{value:msg.value}(ilkKey, joinKey, daiAmount);
  }

	function closeLoanEth(uint256 cdp) public {
		DaiToken daiToken = DaiToken(vanir.mcdAddressProvider().getAddress("MCD_DAI"));

		uint256 outstandingDebt = vanir.getOutstandingDebt(address(this), cdp);
		daiToken.approve(address(vanir), toPrecision(outstandingDebt, vanir.decimals(), daiToken.decimals()));

		vanir.closeLoanEth(payable(address(this)), cdp);
	}

	receive() external payable {}

	function getLoan(uint i) public view returns (uint256) {
		return vanir.userLoans(address(this), i);
	}

	function last() public view returns (uint256) {
		return vanir.last(address(this));
	}

	function outstanding(uint256 cdp) public view returns (uint256) {
		return vanir.getOutstandingDebt(address(this), cdp);
	}

  function getEth() public view returns (uint256) {
    DaiToken daiToken = DaiToken(vanir.mcdAddressProvider().getAddress("MCD_DAI"));

    return daiToken.balanceOf(address(this));
  }

  function toPrecision(uint256 number, uint256 from, uint256 to) private pure returns(uint256) {
    if(from == to) {
      return number;
    }

    if(from > to) {
      return number / (10 ** (from - to));
    }

    if(to > from) {
      return number * (10 ** (to - from));
    }

    revert("vanir/inconsistent math");
  }
}
