// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import {Utils} from "./utils.sol";
import "../src/periphery/LyraSettlementUtils.sol";
import {BaseTSA} from "../src/tokenizedSubaccounts/BaseTSA.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";
import {CashAsset} from "v2-core/src/assets/CashAsset.sol";
import {DutchAuction} from "v2-core/src/liquidation/DutchAuction.sol";
import {ILiquidatableManager} from "v2-core/src/interfaces/ILiquidatableManager.sol";
import {IMatching} from "../src/interfaces/IMatching.sol";
import {IDepositModule} from "../src/interfaces/IDepositModule.sol";
import {IWithdrawalModule} from "../src/interfaces/IWithdrawalModule.sol";
import {ITradeModule} from "../src/interfaces/ITradeModule.sol";
import {ISpotFeed} from "v2-core/src/interfaces/ISpotFeed.sol";
import {IWrappedERC20Asset} from "v2-core/src/interfaces/IWrappedERC20Asset.sol";
import "../src/tokenizedSubaccounts/CCTSA.sol";
import "openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TokenizedSubAccount} from "../src/tokenizedSubaccounts/TSA.sol";
import "openzeppelin/proxy/transparent/ProxyAdmin.sol";
import {TSAShareHandler} from "../src/tokenizedSubaccounts/TSAShareHandler.sol";


contract DeployTSA is Utils {

  CoveredCallTSA.CCTSAParams public defaultLrtccTSAParams = CoveredCallTSA.CCTSAParams({
    minSignatureExpiry: 5 minutes,
    maxSignatureExpiry: 30 minutes,
    worstSpotBuyPrice: 1.01e18,
    worstSpotSellPrice: 0.99e18,
    spotTransactionLeniency: 1.01e18,
    optionVolSlippageFactor: 0.5e18,
    optionMaxDelta: 0.4e18,
    optionMinTimeToExpiry: 1 days,
    optionMaxTimeToExpiry: 30 days,
    optionMaxNegCash: -100e18,
    feeFactor: 0.01e18
  });


  /// @dev main function
  function run() external {

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("deployer: ", deployer);

    TokenizedSubAccount tsaImplementation = new TokenizedSubAccount();
    ProxyAdmin proxyAdmin = new ProxyAdmin();
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(tsaImplementation),
      address(proxyAdmin),
      abi.encodeWithSelector(tsaImplementation.initialize.selector, "TSA", "TSA", address(0))
    );

    CoveredCallTSA lrtcctsaImplementation = new CoveredCallTSA();

    proxyAdmin.upgradeAndCall(
      ITransparentUpgradeableProxy(address(proxy)),
      address(lrtcctsaImplementation),
      abi.encodeWithSelector(
        lrtcctsaImplementation.initialize.selector,
        deployer,
        BaseTSA.BaseTSAInitParams({
          subAccounts: ISubAccounts(_getCoreContract("subAccounts")),
          auction: DutchAuction(_getCoreContract("auction")),
          cash: CashAsset(_getCoreContract("cash")),
          wrappedDepositAsset: IWrappedERC20Asset(_getMarketAddress("ETH", "base")),
          manager: ILiquidatableManager(_getCoreContract("srm")),
          matching: IMatching(_getMatchingModule("matching")),
          symbol: "ETH",
          name: "ETH Covered Call"
        }),
        CoveredCallTSA.CCTSAInitParams({
          baseFeed: ISpotFeed(_getMarketAddress("ETH", "spotFeed")),
          depositModule: IDepositModule(_getMatchingModule("deposit")),
          withdrawalModule: IWithdrawalModule(_getMatchingModule("withdrawal")),
          tradeModule: ITradeModule(_getMatchingModule("trade")),
          optionAsset: IOptionAsset(_getMarketAddress("ETH", "option"))
        })
      )
    );

    CoveredCallTSA(address(proxy)).setTSAParams(
      BaseTSA.TSAParams({
        depositCap: 10000000e18,
        minDepositValue: 0.01e18,
        depositScale: 1e18,
        withdrawScale: 1e18,
        managementFee: 0,
        feeRecipient: address(0)
      })
    );
    CoveredCallTSA(address(proxy)).setCCTSAParams(defaultLrtccTSAParams);

    TSAShareHandler shareHandler = new TSAShareHandler();

    string memory objKey = "tsa-deployment";

    vm.serializeAddress(objKey, "shareHandler", address(shareHandler));
    vm.serializeAddress(objKey, "proxyAdmin", address(proxyAdmin));
    vm.serializeAddress(objKey, "implementation", address(lrtcctsaImplementation));
    string memory finalObj = vm.serializeAddress(objKey, "DNWETH", address(proxy));

    // build path
    _writeToDeployments("tsa", finalObj);
  }



  function _getMatchingModule(string memory module) internal returns (address) {
    return abi.decode(vm.parseJson(_readDeploymentFile("matching"), string.concat(".", module)), (address));
  }

  function _getMarketAddress(string memory marketName, string memory contractName) internal returns (address) {
    return abi.decode(vm.parseJson(_readDeploymentFile(marketName), string.concat(".", contractName)), (address));
  }

  function _getCoreContract(string memory contractName) internal returns (address) {
    return abi.decode(vm.parseJson(_readDeploymentFile("core"), string.concat(".", contractName)), (address));
  }
}