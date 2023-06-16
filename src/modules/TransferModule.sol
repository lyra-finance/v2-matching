// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/access/Ownable2Step.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {IMatchingModule} from "../interfaces/IMatchingModule.sol";
import "../SubAccountsManager.sol";
import "../Matching.sol";
import "./BaseModule.sol";

// Handles transferring assets from one subaccount to another
// Verifies the owner of both subaccounts is the same.
// Only has to sign from one side (so has to call out to the
contract TransferModule is BaseModule {
  struct TransferData {
    uint toAccountId;
    address managerForNewAccount;
    Transfers[] transfers;
  }

  struct Transfers {
    address asset;
    uint subId;
    int amount;
  }

  constructor(Matching _matching) BaseModule(_matching) {}

  /// @dev orders must be in order: [to, from]. From does not need to have any data.
  function matchOrders(VerifiedOrder[] memory orders, bytes memory)
    public
    onlyMatching
    returns (uint[] memory newAccIds, address[] memory newOwners)
  {
    if (orders.length != 2) revert("Invalid transfer orders length");
    if (orders[0].owner != orders[1].owner) revert("Transfer must have same owner");

    TransferData memory data = abi.decode(orders[0].data, (TransferData));

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](data.transfers.length);
    for (uint i = 0; i < data.transfers.length; ++i) {
      // We should probably check that we aren't creating more OI by doing this transfer?
      // Users might for some reason create long and short options in different accounts for free by using this method...

      if (data.toAccountId == 0) {
        uint accountId = matching.accounts().createAccount(address(this), IManager(data.managerForNewAccount));
        console2.log("New accountId:", accountId);
        newAccIds = new uint[](data.transfers.length);
        newAccIds[i] = accountId;
        newOwners = new address[](data.transfers.length);
        newOwners[i] = orders[i].owner;
      }

      transferBatch[i] = ISubAccounts.AssetTransfer({
        asset: IAsset(data.transfers[i].asset),
        fromAcc: orders[i].accountId,
        toAcc: newAccIds[i],
        subId: data.transfers[i].subId,
        amount: data.transfers[i].amount,
        assetData: bytes32(0)
      });
    }

    matching.accounts().submitTransfers(transferBatch, "");

    // Transfer accounts back to matching
    _transferAccounts(orders);
  }
}