// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract PartyBid {
  bool public biddingActive;
  bool public biddingSuccess;
  uint256 public bidTarget;
  uint256 public auctionId;
  uint256 public timelockPeriod;

  uint256 public pooledCapital;
  mapping (address => uint256) public daoParticipants;

  constructor() {
    biddingActive = true;
    biddingSuccess = false;
    bidTarget = 1 ether;
    auctionId = 1;
    timelockPeriod = 60 minutes;
  }

  // Functions to pool capital
  function enterDAO() external payable {
    require(biddingActive == true); // Require bidding to still be active
    require(block.timestamp < timelockPeriod); // Require current time < timelock period
    require(msg.value < bidTarget - pooledCapital); // Require dao entry < (bidTarget - pooledCapital)

    // Log dao entry
    pooledCapital += msg.value;
    daoParticipants[msg.sender] += daoParticipants[msg.sender] + msg.value;
  }

  // Functions to widthdraw pooled capital if unsuccesful
  function exitDAO() external {
    require(biddingActive == false); // Require bidding to no longer be active
    require(biddingSuccess == false); // Require bidding to have failed
    require(block.timestamp > timelockPeriod); // Require current time > timelock
    require(daoParticipants[msg.sender] > 0); // Require that exiter has deposited some capital

    payable(msg.sender).transfer(daoParticipants[msg.sender]);
    daoParticipants[msg.sender] = 0;
  }

  // Functions to bid on piece

  // Functions to accept an external bid post-success
}