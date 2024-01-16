// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import {Utils} from "./utils.sol";
import "v2-core/src/assets/WrappedERC20Asset.sol";


contract DeploySettlementUtils is Utils {
  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address erc20Address = vm.envAddress("ERC20_ADDRESS");

    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("deployer: ", deployer);

    string memory file = _readDeploymentFile("core");

    address subAccounts = abi.decode(vm.parseJson(file, ".subAccounts"), (address));

    // constructor(ISubAccounts _subAccounts, IERC20Metadata _wrappedAsset)
    WrappedERC20Asset wrappedERC20Asset = new WrappedERC20Asset(ISubAccounts(subAccounts), IERC20Metadata(erc20Address));

    console2.log("ERC20 address: ", erc20Address);
    console2.log("WrappedERC20Asset: ", address(wrappedERC20Asset));
  }
}