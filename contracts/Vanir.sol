// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

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

interface CdpManager {
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

contract Vanir {
  uint8 public constant decimals = 18; // Should probably not be smaller than wei (18), as we will lose data when converting msg.value

  uint8 constant weiDecimals = 18;
  uint8 constant wadDecimals = 18;
  uint8 constant rayDecimals = 27;
  uint8 constant radDecimals = 45;

  bytes32 private constant cdpManagerKey = "CDP_MANAGER";
  bytes32 private constant mcdVatKey = "MCD_VAT";
  bytes32 private constant mcdJoinDaiKey = "MCD_JOIN_DAI";
  bytes32 private constant mcdDaiTokenKey = "MCD_DAI";
  bytes32 private constant mcdJugKey = "MCD_JUG";
  bytes32 private constant wEthTokenKey = "ETH";

  struct Loan {
    uint256 cdp;
    bytes32 ilk;
    bytes32 joinKey;
    bytes32 tokenKey;
    uint ink;
    uint art;
  }
  
  struct Ilk {
      uint256 Art;   // Total Normalised Debt     [wad]
      uint256 rate;  // Accumulated Rates         [ray]
      uint256 spot;  // Price with Safety Margin  [ray]
      uint256 line;  // Debt Ceiling              [rad]
      uint256 dust;  // Urn Debt Floor            [rad]
  }

  McdAddressProvider public mcdAddressProvider;

  mapping(address => Loan) public loans;

  constructor(address mcdAddressProviderAddress) {
    mcdAddressProvider = McdAddressProvider(mcdAddressProviderAddress);
  }

  error UintError(uint256);

  function openLoanETH(bytes32 ilkKey, bytes32 joinKey, address usr, uint daiAmount) public payable {
    require(loans[usr].cdp == 0, "vanir/sender already has a loan");

    CdpManager manager = CdpManager(mcdAddressProvider.getAddress(cdpManagerKey));
    McdJoin join = McdJoin(mcdAddressProvider.getAddress(joinKey));
    McdJoinDai joinDai = McdJoinDai(mcdAddressProvider.getAddress(mcdJoinDaiKey));
    McdJug jug = McdJug(mcdAddressProvider.getAddress(mcdJugKey));
    McdVat vat = McdVat(mcdAddressProvider.getAddress(mcdVatKey));
    WEthToken wEth = WEthToken(mcdAddressProvider.getAddress(wEthTokenKey));

    require(msg.value > 0, "Value is 0");

    //Wrap ETH
    wEth.deposit{value:msg.value}();
    
    // Update rate, so we don't have to pay unneccesary interest
    jug.drip(ilkKey);

    // Open vault
    manager.open(ilkKey, address(this));
    uint256 cdp = manager.last(address(this));

    // ink and art with internal decimals
    // ink is amount of collateral locked in
    // art is normalized debt, ie debt devided by current rate, so if you want x dai art should be x / rate
    (,uint256 rate,,,) = vat.ilks(ilkKey);
    uint256 ink = toPrecision(wEth.balanceOf(address(this)), wEth.decimals(), decimals);
    uint256 art = ((daiAmount * (10 ** rayDecimals)) / rate) + 1;
    
    // Transfer collateral to vault
    wEth.approve(address(join), toPrecision(msg.value, wadDecimals, wEth.decimals()));
    join.join(manager.urns(cdp), toPrecision(ink, decimals, join.dec()));

    // Lock in wEth and generate dai
    manager.frob(cdp, int(toPrecision(ink, decimals, wadDecimals)), int(toPrecision(art, decimals, wadDecimals)));
    
    // Move dai out of vault
    manager.move(cdp, address(this), toPrecision(daiAmount, decimals, radDecimals));
    vat.hope(address(joinDai));
    joinDai.exit(usr, toPrecision(daiAmount, decimals, wadDecimals));

    // store loan info
    loans[usr] = Loan(cdp, ilkKey, joinKey, "", ink, art);
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
