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

  /**
   * Enables joining the DAO
   */
  function join(uint256 _value) external {
    require(bidPlaced == false); // dont allow joining once bid is placed
    require(msg.value == _value); // enforce correct value
    require(daoStakes[address].add(_value).add(currentRaisedAmount) <= bidAmount);

    currentRaisedAmount += currentRaisedAmount.add(_value);
    daoStakes[msg.sender] += daoStakes[msg.sender].add(_value);
  }

  function _exitIfBidFailed() internal payable {
    require(bidPlaced == true); // check if bid was placed
    require(address(this).balance == bidAmount); // contract should have funds if not top bidder
    require(daoStakes[msg.sender] > 0); // check if individual is a dao member

    payable(msg.sender).send(daoStakes[msg.sender]);
    daoStakes[msg.sender] = 0;
  }

  function _exitIfTimeoutPassed() internal payable {
    require(bidPlaced == false); // check if bid was not placed
    require(block.timestamp >= exitTimeout); // make sure current time > maxTimeout
  }
}