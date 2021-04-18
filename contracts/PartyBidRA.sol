// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.8;

// ============ Imports ============

import { ReserveAuctionV3 } from "./flattened/ReserveAuctionV3.sol";
import { SafeMath } from "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";

// ============ Interface declarations ============

// Wrapped Ether
interface IWETH {
  function balanceOf(address src) external view returns (uint256);
  function transferFrom(address src, address dst, uint256 wad) external returns (bool);
}

// ERC721
interface IERC721 {
  function ownerOf(uint256 tokenId) external view returns (address);
  function transferFrom(address from, address to, uint256 tokenId) external view;
}

// @dev: Must use wETH for all outgoing transactions, since returned capital from contract will
//       always be wETH (due to hard 30,000 imposed gas limitation at ETH transfer layer).
contract PartyBid {
  // Use OpenZeppelin library for SafeMath
  using SafeMath for uint256;

  // ============ Immutable storage ============

  // Address of the Reserve Auction contract to place bid on
  address public immutable ReserveAuctionV3Address;
  // Address of the wETH contract
  address public immutable wETHAddress;
  // Address of the NFT contract
  address public immutable NFTAddress;

  // ============ Mutable storage ============

  // ReserveAuctionV3 auctionID to bid on
  uint256 public auctionID;
  // Amount that DAO will bid for on ReserveAuctionV3 item
  uint256 public bidAmount;
  // Current amount raised to bid on ReserveAuctionV3 item
  uint256 public currentRaisedAmount;
  // Maximum time to wait for dao members to fill contract before enabling exit
  uint256 public exitTimeout; 
  // Price set by DAO members to sell NFT (default: max(uint256) in constructor)
  uint256 public NFTSalePrice;
  // Toggled when DAO places bid to purchase a ReserveAuctionV3 item
  bool public bidPlaced;
  // Toggled when DAO has resold won ReserveAuctionV3 item (to enable exit liquidity)
  bool public NFTResold;
  // Stakes of individual dao members
  mapping (address => uint256) public daoStakes;
  // List of active proposals to set NFT price
  NFTPriceProposal[] public NFTPriceProposals;
  // List of supporters for each active proposal
  mapping (uint256 => mapping (address => bool)) NFTPriceProposalSupporters;

  // ============ Structs ============

  // Individual price proposals
  struct NFTPriceProposal {
    address proposer; // Proposing DAO member
    uint256 price; // Price proposed for NFT sale
    uint256 aggregateSupport; // sum(balance(voting_addresses_in_favor))
  }

  // ============ Modifiers ============
  
  // Reverts if the DAO has not won the NFT
  modifier onlyIfAuctionWon() {
    // Ensure that owner of NFT(auctionId) is contract address
    require(IERC721(NFTAddress).ownerOf(auctionID) == address(this), "PartyBid: DAO has not won auction.");
    _;
  }

  // ============ Events ============

  // Address of a new DAO member and their entry share
  event PartyJoined(address indexed member, uint256 value);
  // Value of newly placed bid on ReserveAuctionV3 item
  event PartyBidPlaced(uint256 auctionID, uint256 value);
  // Address and exit share of DAO member, along with reason for exit
  event PartyMemberExited(address indexed member, uint256 value, bool postFailure);
  // Proposer of new NFT sale price and proposed price
  event PartyNFTPriceProposed(address indexed proposer, uint256 price);
  // NFT sale price proposal ID and voter address
  event PartyNFTPriceProposalVoted(uint256 indexed proposalId, address voter);
  // Executed NFT sale price proposal ID and price
  event PartyNFTPriceProposalExecuted(uint256 indexed proposalId, uint256 price);
  // NFT sale capturing purchasing address, price
  event PartyNFTSold(address indexed buyer, uint256 price);

  // ============ Constructor ============

  constructor(
    address _ReserveAuctionV3Address,
    uint256 _auctionID,
    uint256 _bidAmount,
    uint256 _exitTimeout
  ) public {
    // Initialize immutable memory
    ReserveAuctionV3Address = _ReserveAuctionV3Address;
    wETHAddress = ReserveAuctionV3(_ReserveAuctionV3Address).wethAddress();
    NFTAddress = ReserveAuctionV3(_ReserveAuctionV3Address).nftContract();

    // Initialize mutable memory
    auctionID = _auctionID;
    bidAmount = _bidAmount;
    currentRaisedAmount = 0;
    exitTimeout = _exitTimeout;
    bidPlaced = false;
    NFTResold = false;
    NFTSalePrice = 2**256 - 1;
  }

  // ============ Join the DAO ============

  /**
   * Join the DAO by sending ETH
   * Requires bidding to be enabled, forced matching of deposit value to sent eth, and there to be capacity in DAO
   */
  function join(uint256 _value) external payable {
    // Dont allow joining once the bid has already been placed
    require(bidPlaced == false, "PartyBid: Cannot join since bid has been placed.");
    // Ensure matching of deposited value to ETH sent to contract
    require(msg.value == _value, "PartyBid: Deposit amount does not match spent ETH.");
    // Ensure sum(eth sent, current raised) <= required bid amount
    require(_value.add(currentRaisedAmount) <= bidAmount, "PartyBid: DAO does not have capacity.");

    currentRaisedAmount = currentRaisedAmount.add(_value); // Increment raised amount
    daoStakes[msg.sender] = daoStakes[msg.sender].add(_value); // Track DAO member contribution

    emit PartyJoined(msg.sender, _value); // Emit new DAO member
  }

  // ============ Place a bid from DAO ============

  /**
   * Execute bid placement, as DAO member, so long as required conditions are met
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

    emit PartyBidPlaced(auctionID, bidAmount); // Emit bid placed
  }

  // ============ ReserveAuctionV3 NFT re-auctioning ============

  /**
   * Returns boolean status of if DAO has won NFT
   */
  function NFTWon() public view returns (bool) {
    // Check if owner of NFT(auctionID) is contract address
    return IERC721(NFTAddress).ownerOf(auctionID) == address(this);
  }

  /**
   * Enables DAO member to propose a new price to sell the won NFT for
   */
  function NFTProposePrice(uint256 _price) external onlyIfAuctionWon() returns (uint256) {
    // Ensure that caller is a DAO member
    require(daoStakes[msg.sender] > 0, "PartyBid: Must first be a DAO member to exit DAO.");

    // Collect proposalId from proposals array length
    uint256 proposalId = NFTPriceProposals.length;

    // Append new proposal with existing support starting at power(msg.sender)
    NFTPriceProposals[proposalId] = NFTPriceProposal(
      msg.sender,
      _price,
      // Existing aggregate support starts at power(proposer)
      daoStakes[msg.sender]
    );

    // Emit both new proposal and new voter (proposer)
    emit PartyNFTPriceProposed(msg.sender, _price);
    emit PartyNFTPriceProposalVoted(proposalId, msg.sender);

    // Update supporters mapping
    NFTPriceProposalSupporters[proposalId][msg.sender] = true;

    return proposalId;
  }

  /**
   * Enables DAO member to vote in favor of a proposal that proposes a new price to sell the won NFT for
   */
  function NFTVoteForPriceProposal(uint256 _proposalId) external onlyIfAuctionWon() {
    // Ensure that caller is a DAO member
    require(daoStakes[msg.sender] > 0, "PartyBid: Must first be a DAO member to exit DAO.");
    // Ensure that caller has not already voted in favor of proposal
    require(NFTPriceProposalSupporters[_proposalId][msg.sender] != true, "PartyBid: Cannot vote for a proposal twice.");

    // Increment aggregate support with power(voter)
    NFTPriceProposals[_proposalId].aggregateSupport = NFTPriceProposals[_proposalId].aggregateSupport.add(daoStakes[msg.sender]);

    // Update supporters mapping
    NFTPriceProposalSupporters[_proposalId][msg.sender] = true;

    emit PartyNFTPriceProposalVoted(_proposalId, msg.sender);
  }

  /**
   * Set the standing purchase price for the won NFT
   */
  function NFTSetPrice(uint256 _proposalId) external onlyIfAuctionWon() {
    // Ensure that caller is a DAO member
    require(daoStakes[msg.sender] > 0, "PartyBid: Must first be a DAO member to exit DAO.");
    // Ensure that the proposal being enacted has > 50% of supporting DAO vote
    require(NFTPriceProposals[_proposalId].aggregateSupport > currentRaisedAmount.div(2), "PartyBid: Insufficient support to set NFT price.");

    // Update NFT price
    NFTSalePrice = NFTPriceProposals[_proposalId].price;

    // Nullify proposal aggregate support to prevent resetting price via same proposal in future
    NFTPriceProposals[_proposalId].aggregateSupport = 0;

    emit PartyNFTPriceProposalExecuted(_proposalId, NFTSalePrice);
  }

  /**
   * Enables third-party to purchase won NFT at currently set price
   */
  function buyNFTAtPrice(uint256 _value) external payable onlyIfAuctionWon() {
    // Ensure matching of bid value to ETH sent to contract
    require(msg.value == _value, "PartyBid: Bid amount does not match spent ETH.");
    // Ensure bid value is = NFT sale price set by DAO members
    require(msg.value == NFTSalePrice, "PartyBid: Bid is below NFT sale price.");

    // Transfer NFT to bidder
    IERC721(NFTAddress).transferFrom(address(this), msg.sender, auctionID);
    NFTResold = true;

    emit PartyNFTSold(msg.sender, msg.value);
  }

  // ============ Exit the DAO ============

  /**
   * Exit DAO if bid was won, and NFT was resold for NFTSalePrice
   */
  function _exitPostSale() internal {
    // Require NFT to have already have been resold
    require(NFTResold = true, "PartyBid: NFT has not yet been resold.");
    // Failsafe: Ensure contract has non-zero funds to payout DAO members
    require(address(this).balance > 0, "PartyBid: DAO is insolvent.");

    // Send calculated share of NFTSalePrice based on DAO membership share
    payable(msg.sender).transfer(
      // Multiply final NFT sale price
      NFTSalePrice.mul(
        // By (dao_share / total)
        daoStakes[msg.sender].div(currentRaisedAmount)
      )
    );
    emit PartyMemberExited(msg.sender, daoStakes[msg.sender], false);

    // Nullify member DAO share
    daoStakes[msg.sender] = 0;
  }
  
  /**
   * Exit DAO if bid was beaten
   * @dev Capital returned in form of wETH due to 30,000 gas transfer limit imposed by ReserveAuctionV3
   */
  function _exitIfBidFailed() internal {
    // Dont allow exiting via this function if bid hasn't been placed
    require(bidPlaced == true, "PartyBid: Bid must be placed to exit via failure.");
    // Ensure that contract wETH balance is > 0 (implying that either funds have been returned or wETH airdropped)
    require(IWETH(wETHAddress).balanceOf(address(this)) > 0, "PartyBid: DAO bid has not been beaten or refunded yet.");

    // Transfer wETH from contract to DAO member and emit event
    IWETH(wETHAddress).transferFrom(address(this), msg.sender, daoStakes[msg.sender]);
    currentRaisedAmount = currentRaisedAmount.sub(daoStakes[msg.sender]);
    emit PartyMemberExited(msg.sender, daoStakes[msg.sender], true);

    // Nullify member DAO share
    daoStakes[msg.sender] = 0;
  }

  /**
   * Exit DAO if deposit timeout has passed
   */
  function _exitIfTimeoutPassed() internal {
    // Dont allow exiting via this function if bid has been placed
    require(bidPlaced == false, "PartyBid: Bid must be pending to exit via timeout.");
    // Ensure that current time > deposit timeout
    require(block.timestamp >= exitTimeout, "PartyBid: Exit timeout not met.");

    // Transfer ETH from contract to DAO member and emit event
    payable(msg.sender).transfer(daoStakes[msg.sender]);
    currentRaisedAmount = currentRaisedAmount.sub(daoStakes[msg.sender]);
    emit PartyMemberExited(msg.sender, daoStakes[msg.sender], false);

    // Nullify member DAO share
    daoStakes[msg.sender] = 0;
  }

  /**
   * Public utility function to call internal exit functions based on bid state
   */
  function exit() external payable {
    // Ensure that caller is a DAO member
    require(daoStakes[msg.sender] > 0, "PartyBid: Must first be a DAO member to exit DAO.");

    if (NFTResold) {
      // If NFT has already been resold, allow post-sale exit
      _exitPostSale();
    } else {
      if (bidPlaced) {
        // If bid has been placed, allow exit on bid failure
        _exitIfBidFailed();
      } else {
        // Else, allow exit when exit timeout window has passed
        _exitIfTimeoutPassed();
      }
    }
  }
}