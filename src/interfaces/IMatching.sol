// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IOrderVerifier} from "./IOrderVerifier.sol";

interface IMatching is IOrderVerifier {
  function tradeExecutors(address tradeExecutor) external view returns (bool canExecute);
  function allowedModules(address tradeExecutor) external view returns (bool canExecute);

  error M_AccountNotReturned();
  error M_AccountAlreadyExists();
  error M_ArrayLengthMismatch();
  error M_OnlyAllowedModule();
  error M_OnlyTradeExecutor();

  ////////////
  // Events //
  ////////////

  event TradeExecutorSet(address indexed executor, bool canExecute);
  event ModuleAllowed(address indexed module, bool allowed);
}