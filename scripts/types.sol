// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Matching} from "../src/Matching.sol";
import {DepositModule} from "../src/modules/DepositModule.sol";
import {RiskManagerChangeModule} from "../src/modules/RiskManagerChangeModule.sol";
import {TradeModule} from "../src/modules/TradeModule.sol";
import {TransferModule} from "../src/modules/TransferModule.sol";
import {WithdrawalModule} from "../src/modules/WithdrawalModule.sol";


struct NetworkConfig { 
  address subAccounts;
  address cashAsset;
}

struct Deployment {
  // matching contract
  Matching matching;
  // modules
  DepositModule deposit;
  RiskManagerChangeModule rmChange;
  TradeModule trade;
  TransferModule transfer;
  WithdrawalModule withdrawal;
}