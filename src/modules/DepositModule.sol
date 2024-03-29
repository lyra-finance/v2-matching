// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

// Inherited
import {BaseModule} from "./BaseModule.sol";
import {IDepositModule} from "../interfaces/IDepositModule.sol";
// Interfaces
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {IERC20BasedAsset} from "v2-core/src/interfaces/IERC20BasedAsset.sol";
import {IMatching} from "../interfaces/IMatching.sol";

/**
 * @dev Handles depositing ERC20 Asset into subAccount
 */
contract DepositModule is IDepositModule, BaseModule {
  constructor(IMatching _matching) BaseModule(_matching) {}

  function executeAction(VerifiedAction[] memory actions, bytes memory)
    external
    onlyMatching
    returns (uint[] memory newAccIds, address[] memory newAccOwners)
  {
    // Verify
    if (actions.length != 1) revert DM_InvalidDepositActionLength();
    VerifiedAction memory action = actions[0];
    _checkAndInvalidateNonce(action.owner, action.nonce);

    // Execute
    DepositData memory data = abi.decode(actions[0].data, (DepositData));

    uint subaccountId = action.subaccountId;
    if (subaccountId == 0) {
      subaccountId = subAccounts.createAccount(address(this), IManager(data.managerForNewAccount));

      newAccIds = new uint[](1);
      newAccIds[0] = subaccountId;
      newAccOwners = new address[](1);
      newAccOwners[0] = action.owner;
    }

    IERC20Metadata depositToken = IERC20BasedAsset(data.asset).wrappedAsset();

    uint depositAmount = data.amount;
    if (data.amount == type(uint).max) {
      depositAmount = depositToken.balanceOf(action.owner);
    }

    depositToken.transferFrom(action.owner, address(this), depositAmount);

    depositToken.approve(address(data.asset), depositAmount);
    IERC20BasedAsset(data.asset).deposit(subaccountId, depositAmount);

    // Return
    _returnAccounts(actions, newAccIds);
    return (newAccIds, newAccOwners);
  }
}
