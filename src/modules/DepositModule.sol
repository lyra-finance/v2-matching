// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "v2-core/interfaces/IManager.sol";
import "v2-core/interfaces/IERC20BasedAsset.sol";

import "../interfaces/IMatchingModule.sol";
import "./BaseModule.sol";
// import "../interfaces/IERC20BasedAsset.sol";

// Handles transferring assets from one subaccount to another
// Verifies the owner of both subaccounts is the same.
// Only has to sign from one side (so has to call out to the
contract DepositModule is BaseModule {
  struct DepositData {
    address asset;
    uint amount;
    address managerForNewAccount;
  }

  constructor(Matching _matching) BaseModule(_matching) {}

  function matchOrders(VerifiedOrder[] memory orders, bytes memory)
    public
    returns (uint[] memory accountIds, address[] memory owners)
  {
    if (orders.length != 1) revert("Invalid withdrawal orders length");

    _checkAndInvalidateNonce(orders[0].owner, orders[0].nonce);

    DepositData memory data = abi.decode(orders[0].data, (DepositData));
    uint accountId = orders[0].accountId;
    if (accountId == 0) {
      accountId = matching.accounts().createAccount(address(this), IManager(data.managerForNewAccount));
    }

    IERC20Metadata depositToken = IERC20BasedAsset(data.asset).wrappedAsset();

    depositToken.transferFrom(orders[0].owner, address(this), data.amount);
    depositToken.approve(address(data.asset), data.amount);

    IERC20BasedAsset(data.asset).deposit(orders[0].accountId, data.amount);

    matching.accounts().transferFrom(address(this), address(matching), orders[0].accountId);
  }
}