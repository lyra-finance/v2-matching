// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

// Libraries
import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";

// Inherited
import {BaseModule} from "./BaseModule.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {ITradeModule} from "../interfaces/ITradeModule.sol";

// Interfaces
import {IMatchingModule} from "../interfaces/IMatchingModule.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IAsset} from "v2-core/src/interfaces/IAsset.sol";
import {IPerpAsset} from "v2-core/src/interfaces/IPerpAsset.sol";
import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";
import {IMatching} from "../interfaces/IMatching.sol";

contract TradeModule is ITradeModule, BaseModule, Ownable2Step {
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;
  using DecimalMath for uint;

  // @dev we fix the quoteAsset for the contracts so we only support one quoteAsset per deployment
  IAsset public immutable quoteAsset;

  mapping(IPerpAsset => bool) public isPerpAsset;

  uint public feeRecipient;

  /// @dev we trust the nonce is unique for the given "VerifiedOrder" for the owner
  mapping(address owner => mapping(uint nonce => uint filled)) public filled;

  // @dev we want to make sure once submitted with one nonce, we cant submit a different order with the same nonce
  // note; it is still possible to submit different orders, but all parameters will match (but expiry may be different)
  mapping(address owner => mapping(uint nonce => bytes32 hash)) public seenNonces;

  constructor(IMatching _matching, IAsset _quoteAsset, uint _feeRecipient) BaseModule(_matching) Ownable2Step() {
    quoteAsset = _quoteAsset;
    feeRecipient = _feeRecipient;
  }

  ///////////
  // Admin //
  ///////////

  function setFeeRecipient(uint _feeRecipient) external onlyOwner {
    feeRecipient = _feeRecipient;
  }

  function setPerpAsset(IPerpAsset _perpAsset, bool isPerp) external onlyOwner {
    isPerpAsset[_perpAsset] = isPerp;
  }

  ////////////////////
  // Action Handler //
  ////////////////////

  /// @dev Assumes VerifiedOrders are sorted in the order: [takerAccount, ...makerAccounts]
  function executeAction(VerifiedOrder[] memory orders, bytes memory actionDataBytes)
    public
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    // Verify
    if (orders.length <= 1) revert TM_InvalidOrdersLength();

    ActionData memory actionData = abi.decode(actionDataBytes, (ActionData));

    OptionLimitOrder memory matchedOrder = OptionLimitOrder({
      accountId: orders[0].accountId,
      owner: orders[0].owner,
      nonce: orders[0].nonce,
      data: abi.decode(orders[0].data, (TradeData))
    });

    if (matchedOrder.accountId != actionData.takerAccount) revert TM_SignedAccountMismatch();

    // We can prepare the transfers as we iterate over the data
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](orders.length * 3 - 2);

    uint totalFilled;
    int worstPrice = matchedOrder.data.isBid ? int(0) : type(int).max;

    for (uint i = 1; i < orders.length; i++) {
      FillDetails memory fillDetails = actionData.fillDetails[i - 1];

      OptionLimitOrder memory makerOrder = OptionLimitOrder({
        accountId: orders[i].accountId,
        owner: orders[i].owner,
        nonce: orders[i].nonce,
        data: abi.decode(orders[i].data, (TradeData))
      });

      _verifyFilledAccount(makerOrder, fillDetails.filledAccount);
      if (makerOrder.data.isBid == matchedOrder.data.isBid) revert TM_IsBidMismatch();

      _fillLimitOrder(makerOrder, fillDetails);
      _addAssetTransfers(transferBatch, fillDetails, matchedOrder, makerOrder, i * 3 - 3);

      totalFilled += fillDetails.amountFilled;
      if (matchedOrder.data.isBid) {
        if (fillDetails.price > worstPrice) worstPrice = fillDetails.price;
      } else {
        if (fillDetails.price < worstPrice) worstPrice = fillDetails.price;
      }
    }

    transferBatch[transferBatch.length - 1] = ISubAccounts.AssetTransfer({
      asset: quoteAsset,
      subId: 0,
      amount: int(actionData.takerFee),
      fromAcc: matchedOrder.accountId,
      toAcc: feeRecipient,
      assetData: bytes32(0)
    });

    _fillLimitOrder(
      matchedOrder,
      FillDetails({
        filledAccount: matchedOrder.accountId,
        amountFilled: totalFilled,
        price: worstPrice,
        fee: actionData.takerFee,
        perpDelta: 0
      })
    );

    // Execute
    subAccounts.submitTransfers(transferBatch, actionData.managerData);

    // Return
    _returnAccounts(orders, newAccIds);
    return (newAccIds, newAccOwners);
  }

  function _verifyFilledAccount(OptionLimitOrder memory order, uint filledAccount) internal view {
    if (order.data.recipientId == 0) revert TM_InvalidRecipientId();
    if (order.accountId != filledAccount) revert TM_SignedAccountMismatch();
    // If the recipient isn't the signed account, verify the owner matches
    if (order.data.recipientId != order.accountId && matching.subAccountToOwner(order.data.recipientId) != order.owner)
    {
      revert TM_InvalidRecipientId();
    }
  }

  function _fillLimitOrder(OptionLimitOrder memory order, FillDetails memory fill) internal {
    int finalPrice = fill.price;

    if (fill.fee.divideDecimal(fill.amountFilled) > order.data.worstFee) revert("fee too high");

    if (order.data.isBid) {
      if (finalPrice > order.data.worstPrice) revert("price too high");
    } else {
      if (finalPrice < order.data.worstPrice) revert("price too low");
    }
    filled[order.owner][order.nonce] += fill.amountFilled;
    if (filled[order.owner][order.nonce] > uint(order.data.desiredAmount)) revert("too much filled");
  }

  function _addAssetTransfers(
    ISubAccounts.AssetTransfer[] memory transferBatch,
    FillDetails memory fillDetails,
    OptionLimitOrder memory matchedOrder,
    OptionLimitOrder memory filledOrder,
    uint startIndex
  ) internal view {
    int amtQuote;
    if (_isPerp(matchedOrder.data.asset)) {
      int perpDelta = _getPerpDelta(matchedOrder.data.asset, fillDetails.price);
      amtQuote = perpDelta.multiplyDecimal(int(fillDetails.amountFilled));
      console2.log("perpDelta", perpDelta);
      console2.log("fillDetails.price", fillDetails.price);
    } else {
      amtQuote = fillDetails.price.multiplyDecimal(int(fillDetails.amountFilled));
    }

    bool isBidder = matchedOrder.data.isBid;

    transferBatch[startIndex] = ISubAccounts.AssetTransfer({
      asset: quoteAsset,
      subId: 0,
      // if the matched trader is the bidder, they are paying the quote asset, otherwise they are receiving it
      amount: isBidder ? amtQuote : -amtQuote,
      fromAcc: isBidder ? matchedOrder.accountId : matchedOrder.data.recipientId,
      toAcc: isBidder ? filledOrder.data.recipientId : filledOrder.accountId,
      assetData: bytes32(0)
    });

    transferBatch[startIndex + 1] = ISubAccounts.AssetTransfer({
      asset: IAsset(matchedOrder.data.asset),
      subId: matchedOrder.data.subId,
      amount: isBidder ? int(fillDetails.amountFilled) : -int(fillDetails.amountFilled),
      fromAcc: isBidder ? filledOrder.accountId : filledOrder.data.recipientId,
      toAcc: isBidder ? matchedOrder.data.recipientId : matchedOrder.accountId,
      assetData: bytes32(0)
    });

    transferBatch[startIndex + 2] = ISubAccounts.AssetTransfer({
      asset: quoteAsset,
      subId: 0,
      amount: int(fillDetails.fee),
      fromAcc: filledOrder.accountId,
      toAcc: feeRecipient,
      assetData: bytes32(0)
    });
  }

  function _isPerp(address baseAsset) internal view returns (bool) {
    return isPerpAsset[IPerpAsset(baseAsset)];
  }

  // Difference between the perp price and the traded price
  function _getPerpDelta(address perpAsset, int marketPrice) internal view returns (int delta) {
    (uint perpPrice,) = IPerpAsset(perpAsset).getPerpPrice();
    return (marketPrice - perpPrice.toInt256());
  }

  function _checkOrderNonce(VerifiedOrder memory order) internal {
    bytes32 storedHash = seenNonces[order.owner][order.nonce];
    if (storedHash == bytes32(0)) {
      seenNonces[order.owner][order.nonce] = keccak256(order.data);
    } else if (storedHash != keccak256(order.data)) {
      revert TM_InvalidNonce();
    }
  }
}
