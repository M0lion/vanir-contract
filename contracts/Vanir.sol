// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "./Interfaces.sol";

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
	    bytes32 ilk;
    	bytes32 joinKey;
			uint256 cdp;
			address urn;
	}
  
	struct Ilk {
			uint256 Art;   // Total Normalised Debt     [wad]
			uint256 rate;  // Accumulated Rates         [ray]
			uint256 spot;  // Price with Safety Margin  [ray]
			uint256 line;  // Debt Ceiling              [rad]
    	uint256 dust;  // Urn Debt Floor            [rad]
	}

	McdAddressProvider public mcdAddressProvider;

	McdCdpManager manager;
	McdJoinDai joinDai;
	McdVat vat;
	McdJug jug;
	WEthToken wEth;
	DaiToken dai;

	mapping(address => uint256[]) public userLoans;
	mapping(address => mapping(uint256 => Loan)) public loans;

	address private owner;

	constructor(address mcdAddressProviderAddress) {
  		mcdAddressProvider = McdAddressProvider(mcdAddressProviderAddress);
			manager = McdCdpManager(mcdAddressProvider.getAddress(cdpManagerKey));
			joinDai = McdJoinDai(mcdAddressProvider.getAddress(mcdJoinDaiKey));
			vat = McdVat(mcdAddressProvider.getAddress(mcdVatKey));
	  	jug = McdJug(mcdAddressProvider.getAddress(mcdJugKey));
	  	wEth = WEthToken(mcdAddressProvider.getAddress(wEthTokenKey));
			dai = DaiToken(mcdAddressProvider.getAddress(mcdDaiTokenKey));

			owner = msg.sender;
	}

	receive() external payable {}

	function withdraw(uint256 amount) public {
			require(msg.sender == owner, "not allowed");
			payable(owner).transfer(amount);
	}

	function open(bytes32 ilkKey, bytes32 joinKey, uint daiAmount) public payable {
	    McdJoin join = McdJoin(mcdAddressProvider.getAddress(joinKey));

	    require(msg.value > 0, "vanir/value cannot be 0");
			require(daiAmount > 0, "vanir/daiAmount cannot be 0");

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
			flushDai(cdp);

	    // store loan info
			userLoans[msg.sender].push(cdp);
    	loans[msg.sender][cdp] = Loan(ilkKey, joinKey, cdp, manager.urns(cdp));
	}

	function last(address usr) public view returns (uint256) {
		return userLoans[usr][userLoans[usr].length - 1];
	}

	function close(address payable usr, uint256 cdp) public {
		Loan memory loan = loans[usr][cdp];
		require(loan.urn != address(0), "vanir/loan does not exist");
		require(msg.sender == usr, "vanir/can only close own loan");

		// Get outstanding debt
		uint256 outstandingDebt = debt(usr, cdp);

		// Make sure we have enough allowance
		require(toPrecision(dai.allowance(usr, address(this)), dai.decimals(), decimals) >= outstandingDebt, "vanir/insufficient allowance");

		// Transfer dai to self
		dai.transferFrom(usr, address(this), outstandingDebt);

		// Transfer dai to vault
		dai.approve(address(joinDai), outstandingDebt);
		joinDai.join(manager.urns(cdp), outstandingDebt);

		(uint256 ink, uint256 art) = vat.urns(loan.ilk, loan.urn);
		// Lock in dai and free up collateral
		// TODO: Dont convert precision
		manager.frob(cdp, -int256(toPrecision(ink, decimals, wadDecimals)), -int256(toPrecision(art, decimals, wadDecimals)));

		flushEth(loan);

		// Clean up loan data
		delete loans[usr][cdp];

		// Remove loan from userLoans[usr]
		bool found = false;
		for(uint i = 0; i < userLoans[usr].length - 1; i++) {
			if(userLoans[usr][i] == cdp) {
				found = true;
			}

			if(found) {
				userLoans[usr][i] = userLoans[usr][i + 1];
			}
		}

		if(found) {
			userLoans[usr].pop();
		} else if (userLoans[usr][userLoans[usr].length - 1] == cdp) {
			userLoans[usr].pop();
		} else {
			revert("Vanir/Could not find loan");
		}
	}

	function debt(address usr, uint256 cdp) public view returns (uint256) {
		Loan memory loan = loans[usr][cdp];
		require(loan.urn != address(0), "Vanir/loan does not exist");

		(, uint256 rate, , , ) = vat.ilks(loan.ilk);
		(, uint256 art) = vat.urns(loan.ilk, loan.urn);

		uint256 outstanding = art * rate;

		return toPrecision(outstanding, wadDecimals + rayDecimals, decimals) + 1;
	}

	function urn(address usr, uint256 cdp) public view returns (uint256 ink, uint256 art) {
		Loan memory loan = loans[usr][cdp];
		require(loan.urn != address(0), "Vanir/loan does not exist");

		return vat.urns(loan.ilk, loan.urn);
	}

	function frob(address payable usr, uint256 cdp, int256 dCol, int256 dDebt) public payable {
		require(msg.sender == usr, "Vanir/Can only frob own loan");

		Loan memory loan = loans[usr][cdp];

    // Update rate, so we don't have to pay unneccesary interest
	  jug.drip(loan.ilk);

	  McdJoin join = McdJoin(mcdAddressProvider.getAddress(loan.joinKey));

		// Get rate
	  (,uint256 rate,,,) = vat.ilks(loan.ilk);

		// Calcluate dArt (normalized debt, see open for more explanation)
    int256 dArt = ((dDebt * int256(10 ** rayDecimals)) / int256(rate));

		// Validate payment is correct

		if (dCol > 0) {
				require(dCol == int256(msg.value), "Vanir/Paid amout doesn't match dCol");
				// Prepare for depositing collateral
			
 		   	//Wrap ETH
	    	wEth.deposit{value:uint256(dCol)}();

	    	// Transfer collateral to vault
	    	wEth.approve(address(join), toPrecision(uint256(dCol), wadDecimals, wEth.decimals()));
 		   	join.join(manager.urns(cdp), toPrecision(uint256(dCol), decimals, join.dec()));
		} else {
			require(msg.value == 0, "Vanir/Can't pay ETH when not depositing collateral");
		}

		if (dDebt < 0) {
			// Prepare for depositing dai

			uint256 amount = uint256(-dDebt);

			// Transfer dai to self
			dai.transferFrom(usr, address(this), amount);

			// Transfer dai to vault
			dai.approve(address(joinDai), amount);
			joinDai.join(manager.urns(cdp), amount);
		} else if (dDebt > 0){
			dArt += 1;
		} else {
			dArt = 0;
		}

		manager.frob(cdp, toPrecisionSigned(dCol, decimals, wadDecimals), toPrecisionSigned(dArt, decimals, wadDecimals));
		
		if (dCol < 0) {
			flushEth(loan);
		}

		if (dDebt > 0) {
			flushDai(cdp);
		}
	}

	function flushDai(uint256 cdp) private {
		uint256 amount = vat.dai(manager.urns(cdp));
		manager.move(cdp, address(this), amount);
		vat.hope(address(joinDai));
		joinDai.exit(msg.sender, toPrecision(amount, radDecimals, wadDecimals));
	}

	function flushEth(Loan memory loan) private {
			uint256 amount = vat.gem(loan.ilk, loan.urn);

	    McdJoin join = McdJoin(mcdAddressProvider.getAddress(loan.joinKey));

			// Move collateral out of vault
			manager.flux(loan.cdp, address(this), amount);
			join.exit(address(this), toPrecision(amount, wadDecimals, join.dec()));

			// Unwrap wEth and send back
			wEth.withdraw(toPrecision(amount, decimals, wEth.decimals()));
			payable(msg.sender).transfer(toPrecision(amount, decimals, wadDecimals));
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

	function toPrecisionSigned(int256 number, uint256 from, uint256 to) private pure returns(int256) {
    if(from == to) {
			return number;
	  }

    if(from > to) {
			return number / int256(10 ** (from - to));
		}

		if(to > from) {
			return number * int256(10 ** (to - from));
		}

		revert("vanir/inconsistent math");
	}
}
