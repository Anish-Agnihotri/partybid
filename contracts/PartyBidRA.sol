// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.8;

// ============ Imports ============
import { ReserveAuctionV3 } from "../reserve-auction-v3/ReserveAuctionV3.sol";
import { SafeMath } from "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";

// ============ Interface declerations ============
interface IWETH {
  function balanceOf(address src) external view returns (uint256);
  function transferFrom(address src, address dst, uint256 wad) external returns (bool);
}

// @Dev: Must use wETH for all outgoing transactions, since returned capital from contract will
//       always be wETH (due to hard 30,000 imposed gas limitation at ETH transfer layer).
contract PartyBid {
  // Use OpenZeppelin library for SafeMath
  using SafeMath for uint256;

  // ============ Immutable storage ============

  // Address of the Reserve Auction contract to place bid on
  address public immutable ReserveAuctionV3Address;

  // Address of the wETH contract
  address public immutable wETHAddress;

  // ============ Mutable storage ============

  // ReserveAuctionV3 auctionID to bid on
  uint256 public auctionID;
  // Amount that DAO will bid for on ReserveAuctionV3 item
  uint256 public bidAmount;
  // Current amount raised to bid on ReserveAuctionV3 item
  uint256 public currentRaisedAmount;
  // Maximum time to wait for dao members to fill contract before enabling exit
  uint256 public exitTimeout; 
  // Toggled when DAO places bid to purchase a ReserveAuctionV3 item
  bool public bidPlaced;
  // Stakes of individual dao members
  mapping (address => uint256) public daoStakes;

  // ============ Constructor ============

  constructor(
    address _ReserveAuctionV3Address,
    address _wETHAddress,
    uint256 _auctionID,
    uint256 _bidAmount,
    uint256 _exitTimeout
  ) public {
    // Initialize immutable memory
    ReserveAuctionV3Address = _ReserveAuctionV3Address;
    wETHAddress = _wETHAddress;

    // Initialize mutable memory
    auctionID = _auctionID;
    bidAmount = _bidAmount;
    currentRaisedAmount = 0;
    exitTimeout = _exitTimeout;
    bidPlaced = false;
  }

  // ============ Join the DAO ============

  /**
   * Join the DAO by sending ETH
   * Requires bidding to be enabled, forced matching of deposit value to sent eth, and there to be capacity in DAO
   */
  function join(uint256 _value) external payable {
    // Dont allow joining once the bid has already been placed
    require(bidPlaced == false, "PartyBid: Cannot join since bid has been placed.");
    // Enforce matching of deposited value to ETH sent to contract
    require(msg.value == _value, "PartyBid: Deposit amount does not match spent ETH.");
    // Enforce sum(eth sent, current raised) <= required bid amount
    require(_value.add(currentRaisedAmount) <= bidAmount, "PartyBid: DAO does not have capacity.");

    currentRaisedAmount = currentRaisedAmount.add(_value); // Increment raised amount
    daoStakes[msg.sender] = daoStakes[msg.sender].add(_value); // Track DAO member contribution
  }

  // ============ Place a bid from DAO ============

  /**
   * Execute bid placement, as a DAO member (so long as required conditions are met)
   */
  function placeBid() external {
    // Dont allow placing a bid if already placed
    require(bidPlaced == false, "PartyBid: Bid has already been placed.");
    // Ensure that required bidAmount is matched with currently raised amount
    require(bidAmount == currentRaisedAmount, "PartyBid: Insufficient raised capital to place bid.");
    // Ensure that caller is a DAO member
    require(daoStakes[msg.sender] > 0, "PartyBid: Must be DAO member to initiate placing bid.");

    // Setup auction contract, place bid, toggle bidding status
    ReserveAuctionV3 auction_contract = ReserveAuctionV3(ReserveAuctionV3Address);
    auction_contract.createBid{value: bidAmount}(auctionID, bidAmount);
    bidPlaced = true;
  }

  // ============ Accept incoming ReserveAuctionV3 item ============

  // ============ Bidding + Acceptance functionality for held ReserveAuctionV3 item ============

  // ============ Exit the DAO ============
  
  function _exitIfBidFailed() internal {
    require(bidPlaced == true); // check if bid was placed (double check from caller)
    require(daoStakes[msg.sender] > 0); // check if individual is a dao member
    require(IWETH(wETHAddress).balanceOf(address(this)) > 0); // contract should have been returned funds if not top bidder
    
    IWETH(wETHAddress).transferFrom(address(this), msg.sender, daoStakes[msg.sender]);
    daoStakes[msg.sender] = 0;
  }

  function _exitIfTimeoutPassed() internal {
    require(bidPlaced == false); // check if bid was not placed (double check from caller)
    require(block.timestamp >= exitTimeout); // make sure current time > maxTimeout
    require(daoStakes[msg.sender] > 0); // check if individual is a dao member

    payable(msg.sender).transfer(daoStakes[msg.sender]);
    daoStakes[msg.sender] = 0;
  }

  function exit() external payable {
    require(daoStakes[msg.sender] > 0); // check if individual is a dao member

    if (bidPlaced) {
      _exitIfBidFailed();
    } else {
      _exitIfTimeoutPassed();
    }
  }
}