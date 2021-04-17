// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract PartyBid {
  bool public bidSuccess;
  uint256 public bidTarget;
  uint256 public auctionId;
  uint256 public maxTokenSupply;
  uint256 public timelockPeriod;

  constructor() {
    bidSuccess = false;
    bidTarget = 1 ether;
    auctionId = 1;
    maxTokenSupply = 1000;
    timelockPeriod = 60 minutes;
  }

  // Functions to pool capital

  // Functions to widthdraw pooled capital if unsuccesful

  // Functions to bid on piece

  // Functions to accept an external bid post-success
}