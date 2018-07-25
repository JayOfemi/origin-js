pragma solidity 0.4.23;

import "../../EvolvingRegistry.sol";
import "./Escrow.sol";

contract V01_Listings {
  event ListingIpfsChange(bytes32 ipfsHash);
  event PurchaseStageChange(Stages stage, bytes32 ipfsHash);

  EvolvingRegistry listingRegistry;

  modifier isSeller(uint256 _listingIndex) {
    require(msg.sender == listings[_listingIndex].seller);
    _;
  }

  modifier isBuyer(uint256 _listingIndex, uint256 _purchaseIndex) {
    uint256 globalPurchaseIndex = listings[_listingIndex].purchaseIndices[_purchaseIndex];
    require(msg.sender == purchases[globalPurchaseIndex].buyer);
    _;
  }

  modifier isNotSeller(uint256 _listingIndex) {
    require(msg.sender != listings[_listingIndex].seller);
    _;
  }

  modifier isAtStage(uint256 _listingIndex, uint256 _purchaseIndex, Stages _stage) {
    uint256 globalPurchaseIndex = listings[_listingIndex].purchaseIndices[_purchaseIndex];
    require(purchases[globalPurchaseIndex].stage == _stage);
    _;
  }

  enum Stages {
    BUYER_REQUESTED,
    BUYER_CANCELED,
    SELLER_ACCEPTED,
    SELLER_REJECTED,
    BUYER_FINALIZED,
    SELLER_FINALIZED
  }

  struct Listing {
    address seller;
    bytes32[] ipfsVersions;
    uint256[] purchaseIndices;
  }

  struct Purchase {
    Stages stage;
    address buyer;
    address escrowContract;
  }

  mapping(uint256 => Listing) public listings;

  Purchase[] public purchases;

  constructor(EvolvingRegistry _listingRegistry) public {
    listingRegistry = _listingRegistry;
  }

  function createListing(bytes32 _ipfsHash) public {
    uint256 entryId = listingRegistry.addEntry();
    Listing memory listing = Listing(
      msg.sender,
      new bytes32[](0),
      new uint256[](0)
    );
    listings[entryId] = listing;
    listings[entryId].ipfsVersions.push(_ipfsHash);
    emit ListingIpfsChange(_ipfsHash);
  }

  function updateListing(uint256 _listingIndex, uint256 _currentVersion, bytes32 _ipfsHash)
    public
    isSeller(_listingIndex)
  {
    require(_currentVersion == listings[_listingIndex].ipfsVersions.length - 1);
    listings[_listingIndex].ipfsVersions.push(_ipfsHash);
    emit ListingIpfsChange(_ipfsHash);
  }

  function getListing(uint256 _listingIndex)
    public
    view
    returns (address _seller, bytes32 _ipfsHash, uint256 _purchasesLength)
  {
    return (
      listings[_listingIndex].seller,
      listings[_listingIndex].ipfsVersions[listings[_listingIndex].ipfsVersions.length - 1],
      listings[_listingIndex].purchaseIndices.length
    );
  }

  function getListingVersion(uint256 _listingIndex)
    public
    view
    returns (uint256 _listingVersion)
  {
    return listings[_listingIndex].ipfsVersions.length - 1;
  }

  function requestPurchase(uint256 _listingIndex, bytes32 _ipfsHash)
    public
    payable
    isNotSeller(_listingIndex)
  {
    address escrowContract = (new V01_Escrow).value(msg.value)(msg.sender, listings[_listingIndex].seller);
    purchases.push(Purchase(
      Stages.BUYER_REQUESTED,
      msg.sender,
      escrowContract
    ));
    listings[_listingIndex].purchaseIndices.push(purchases.length - 1);
    emit PurchaseStageChange(Stages.BUYER_REQUESTED, _ipfsHash);
  }

  function cancelPurchaseRequest(uint256 _listingIndex, uint256 _purchaseIndex, bytes32 _ipfsHash)
    public
    payable
    isBuyer(_listingIndex, _purchaseIndex)
    isAtStage(_listingIndex, _purchaseIndex, Stages.BUYER_REQUESTED)
  {
    uint256 globalPurchaseIndex = listings[_listingIndex].purchaseIndices[_purchaseIndex];
    V01_Escrow escrow = V01_Escrow(purchases[globalPurchaseIndex].escrowContract);
    escrow.cancel();
    purchases[globalPurchaseIndex].stage = Stages.BUYER_CANCELED;
    emit PurchaseStageChange(Stages.BUYER_CANCELED, _ipfsHash);
  }

  function acceptPurchaseRequest(uint256 _listingIndex, uint256 _purchaseIndex, bytes32 _ipfsHash)
    public
    payable
    isSeller(_listingIndex)
    isAtStage(_listingIndex, _purchaseIndex, Stages.BUYER_REQUESTED)
  {
    uint256 globalPurchaseIndex = listings[_listingIndex].purchaseIndices[_purchaseIndex];
    purchases[globalPurchaseIndex].stage = Stages.SELLER_ACCEPTED;
    emit PurchaseStageChange(Stages.SELLER_ACCEPTED, _ipfsHash);
  }

  function acceptPurchaseAndUpdateListing(uint256 _listingIndex, uint256 _purchaseIndex, bytes32 _purchaseIpfsHash, uint256 _currentListingVersion, bytes32 _listingIpfsHash)
    public
    payable
    isSeller(_listingIndex)
    isAtStage(_listingIndex, _purchaseIndex, Stages.BUYER_REQUESTED)
  {
    uint256 globalPurchaseIndex = listings[_listingIndex].purchaseIndices[_purchaseIndex];
    purchases[globalPurchaseIndex].stage = Stages.SELLER_ACCEPTED;
    emit PurchaseStageChange(Stages.SELLER_ACCEPTED, _purchaseIpfsHash);
    updateListing(_listingIndex, _currentListingVersion, _listingIpfsHash);
  }

  function rejectPurchaseRequest(uint256 _listingIndex, uint256 _purchaseIndex, bytes32 _ipfsHash)
    public
    payable
    isSeller(_listingIndex)
    isAtStage(_listingIndex, _purchaseIndex, Stages.BUYER_REQUESTED)
  {
    uint256 globalPurchaseIndex = listings[_listingIndex].purchaseIndices[_purchaseIndex];
    V01_Escrow escrow = V01_Escrow(purchases[globalPurchaseIndex].escrowContract);
    escrow.cancel();
    purchases[globalPurchaseIndex].stage = Stages.SELLER_REJECTED;
    emit PurchaseStageChange(Stages.SELLER_REJECTED, _ipfsHash);
  }

  function buyerFinalizePurchase(uint256 _listingIndex, uint256 _purchaseIndex, bytes32 _ipfsHash)
    public
    payable
    isBuyer(_listingIndex, _purchaseIndex)
    isAtStage(_listingIndex, _purchaseIndex, Stages.SELLER_ACCEPTED)
  {
    uint256 globalPurchaseIndex = listings[_listingIndex].purchaseIndices[_purchaseIndex];
    purchases[globalPurchaseIndex].stage = Stages.BUYER_FINALIZED;
    emit PurchaseStageChange(Stages.BUYER_FINALIZED, _ipfsHash);
  }

  function sellerFinalizePurchase(uint256 _listingIndex, uint256 _purchaseIndex, bytes32 _ipfsHash)
    public
    payable
    isSeller(_listingIndex)
    isAtStage(_listingIndex, _purchaseIndex, Stages.BUYER_FINALIZED)
  {
    uint256 globalPurchaseIndex = listings[_listingIndex].purchaseIndices[_purchaseIndex];
    V01_Escrow escrow = V01_Escrow(purchases[globalPurchaseIndex].escrowContract);
    escrow.complete();
    purchases[globalPurchaseIndex].stage = Stages.SELLER_FINALIZED;
    emit PurchaseStageChange(Stages.SELLER_FINALIZED, _ipfsHash);
  }

  function purchasesLength(uint256 _listingIndex) public constant returns (uint) {
    return listings[_listingIndex].purchaseIndices.length;
  }

  function getPurchase(uint256 _listingIndex, uint256 _purchaseIndex)
    public
    constant
    returns (Stages, address, address _escrowContract) {
      uint256 globalPurchaseIndex = listings[_listingIndex].purchaseIndices[_purchaseIndex];
      Purchase memory purchase = purchases[globalPurchaseIndex];
      return (
        purchase.stage,
        purchase.buyer,
        purchase.escrowContract
      );
  }
}