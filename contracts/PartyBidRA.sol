// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { SafeMath } from "../node_modules/@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";

contract PartyBid {
  // Use OpenZeppelin library for SafeMath
  using SafeMath for uint256;

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

  // ============ Join the DAO ============

  /**
   * Join the DAO by sending ETH
   * Requires bidding to be enabled, forced matching of deposit value to sent eth, and there to be capacity in DAO
   */
  function join(uint256 _value) external {
    // Dont allow joining once the bid has already been placed
    require(bidPlaced == false, "PartyBid: Cannot join since bid has been placed.");
    // Enforce matching of deposited value to ETH sent to contract
    require(msg.value == _value, "PartyBid: Deposit amount does not match spent ETH.");
    // Enforce sum(eth sent, current raised) <= required bid amount
    require(_value.add(currentRaisedAmount) <= bidAmount, "PartyBid: DAO does not have capacity.");

    currentRaisedAmount += currentRaisedAmount.add(_value); // Increment raised amount
    daoStakes[msg.sender] += daoStakes[msg.sender].add(_value); // Track DAO member contribution
  }

  // ============ Place a bid from DAO ============

  // ============ Accept incoming ReserveAuctionV3 item ============

  // ============ Bidding + Acceptance functionality for held ReserveAuctionV3 item ============

  // ============ Exit the DAO ============
  
  function _exitIfBidFailed() internal payable {
    require(bidPlaced == true); // check if bid was placed (double check from caller)
    require(address(this).balance == bidAmount); // contract should have been returned funds if not top bidder
    require(daoStakes[msg.sender] > 0); // check if individual is a dao member

    payable(msg.sender).send(daoStakes[msg.sender]);
    daoStakes[msg.sender] = 0;
  }

  function _exitIfTimeoutPassed() internal payable {
    require(bidPlaced == false); // check if bid was not placed (double check from caller)
    require(block.timestamp >= exitTimeout); // make sure current time > maxTimeout
    require(daoStakes[msg.sender] > 0); // check if individual is a dao member

    payable(msg.sender).send(daoStakes[msg.sender]);
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