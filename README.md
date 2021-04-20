<img src="https://i.imgur.com/HYb9lcg.png" alt="PartyBid logo" width="200" />

## Introduction

[Direct link to PartyBid contract.](https://github.com/Anish-Agnihotri/partybid/blob/master/contracts/PartyBidRA.sol)

Inspired by [Denis Nazarov's](https://twitter.com/Iiterature/status/1383238473767813125) tweet about automatic DAO's to bid on NFTs.

PartyBid is a collector DAO that enables individuals to pool capital and bid on [Mirror's reserve auctions](https://github.com/mirror-xyz/reserve-auction-v2) (kudos to the work of [Mirror](https://mirror.xyz), [Mint Fund](https://mint.af/), [Zora](https://zora.co/), and [Billy Rennekamp](https://twitter.com/billyrennekamp)).

PartyBid is a DAO that has few functions. Namely, the ability to pool capital, bid on reserve auctions, take custody of won NFTs, resell those NFTs via Zora and split profits, or if outbid, return capital to participants.

## How does it work?

1. You deploy a DAO with `PartyBidRA.sol`, passing in the address to the `ReserveAuctionV3` contract you are using, the `auctionID` (aka tokenID) of the NFT you are bidding for, your `bidAmount` (scaled to 1e18 for wETH), and the `exitTimeout` (which is the unix timestamp value till when you want the DAO to hold funds and wait for new members).
2. Next, individuals can call `join()` to become members of the DAO, sending in their ETH for a spot.

Now, there are three possibilities:

1. If the DAO is unable to raise `bidAmount` before `exitTimeout`, DAO members can call `exit()` and withdraw their funds. Note, if you have benevolent DAO members, you can still call `placeBid()` after the `exitTimeout` window is up.
2. If the DAO is able to raise `bidAmount`, you can call `placeBid()` to place your DAO's bid. If the DAO is unsuccessful in winning the NFT (aka, you are outbid), DAO members can call `exit()` to withdraw their funds.
3. Finally, if the DAO is able to raise `bidAmount`, you call `placeBid()`, and you win the NFT, you can continue:

Once the DAO has won the NFT from the reserve auction, DAO members have 4 callable functions to resell this NFT:

1. DAO members can call `DAOProposeZoraBid()` to propose new Zora bids against the NFT that the DAO should consider accepting.
2. DAO members can call `DAOVoteForZoraBidProposal()` to vote for these aforementioned proposals that have been put up. A successful proposal needs >50% of the vote to be executed.
3. DAO members can call `DAOExecuteZoraBid()` to execute a proposal that: (1) has greater than 50% of the DAO's voting power, and (2) has not changed since the vote was initiated (to prevent bad actors from changing their bids during the voting process). This will transfer the Zora NFT to the bidder, and accept their funds to the contract.
4. Finally, once a successful resale has occured, DAO members can call `exit()` to reclaim their share of the bid amount.

## Run/deploy

```bash
# Install dependencies
npm run install

# Compile contracts with hardhat
npx hardhat compile
```

Full-form tests coming as soon as I get a chance to sit down and write out all possible state transitions.

The code has been tested extensively against Rinkeby deployments, but I still urge caution when using with real capital since this code is both unaudited and written by a non-full-time Solidity enthusiast.

## Considerations

Due to the simplistic nature of this mvp, there are a few considerations made:

1. For sake of simplicity, joining via only ETH and returning capital + accepting bids denominated in wETH are supported. No other tokens are supported at the moment (for reference, Mirror's Reserve Auctions also only support wETH).
2. The PartyBid DAO is a one-time deployment vehicle that cannot be reused for multiple auctions.
3. The PartyBid DAO does not support Zora's `prevOwner` cutback (aka, if a resold NFT with such cutback is sold by the bidder, the funds accrued to the contract will not be removeable).

## Extensions

1. There is very-well the future possibility to have the DAO itself begin a reserve auction with the won NFT. Sort of like a meta play with RA to RA, and movement between DAOs.
2. Extension to non-Zora NFTs is also possible with some additional logic to create either: (1) an in-contract bid management system, or (2) a price floor at which any third-party can purchase an NFT. A rudimentary, WIP example of the latter is being developed in [aa/general-nft](https://github.com/Anish-Agnihotri/partybid/tree/aa/general-nft).
