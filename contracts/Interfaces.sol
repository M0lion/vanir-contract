// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface McdAddressProvider {
  function getAddress(bytes32 _key) external view returns (address);
}

interface McdJoin {
  function join(address urn, uint256 amt) external;
  function dec() external view returns(uint256);
  function exit(address guy, uint256 amt) external;
}

interface McdJoinDai {
  function exit(address usr, uint256 wad) external;
  function join(address urn, uint256 wad) external;
}

interface McdCdpManager {
  function open(bytes32 ilk, address usr) external;
  function frob(uint cdp, int dink, int dart) external;
  function move(uint cdp, address dst, uint rad) external;
  function last(address input) external view returns(uint256 cdp);
  function urns(uint256 cdp) external view returns(address urn);
  function flux(uint256 cdp, address dst, uint256 wad) external;
}

interface McdVat {
    function ilks(bytes32 ilk) external view returns(uint256, uint256, uint256, uint256, uint256);
    function hope(address usr) external;
    function gem(bytes32 ilk, address urn) external view returns(uint256);
    function dai(address urn) external view returns(uint256);
    function urns(bytes32 ilk, address urn) external view returns(uint256 ink, uint256 art);
}

interface DaiToken {
  function transfer(address dst, uint256 wad) external;
  function transferFrom(address src, address dst, uint256 wad) external;
  function approve(address guy, uint256 wad) external;
  function decimals() external view returns(uint8);
  function allowance(address from, address to) external view returns(uint256);
  function balanceOf(address usr) external view returns(uint256);
}

interface WEthToken {
  function transfer(address dst, uint256 amt) external;
  function transferFrom(address src, address dst, uint256 wad) external;
  function approve(address guy, uint256 wad) external;
  function decimals() external view returns(uint8);
  function allowance(address from, address to) external view returns(uint256);
  function balanceOf(address usr) external view returns(uint256);
  function deposit() external payable;
	function withdraw(uint256 wad) external;
}

interface Token {
  function transfer(address dst, uint256 amt) external;
  function transferFrom(address src, address dst, uint256 wad) external;
  function approve(address guy, uint256 wad) external;
  function decimals() external view returns(uint8);
  function allowance(address from, address to) external view returns(uint256);
  function balanceOf(address usr) external view returns(uint256);
}

interface McdJug {
  function drip(bytes32 ilk) external;
}
