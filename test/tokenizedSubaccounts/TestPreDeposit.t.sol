// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {OptionEncoding} from "lyra-utils/encoding/OptionEncoding.sol";

import {IDutchAuction} from "v2-core/src/interfaces/IDutchAuction.sol";
import {IManager} from "v2-core/src/interfaces/IManager.sol";
import {ITradeModule} from "../../src/interfaces/ITradeModule.sol";
import {ISubAccounts} from "v2-core/src/interfaces/ISubAccounts.sol";

import "forge-std/console2.sol";
import "./TSATestUtils.sol";

contract TSAPreDepositTest is TSATestUtils {
  MockERC20 internal erc20;
  TokenizedSubAccount internal tsa;

  function setUp() public override {
    erc20 = new MockERC20("token", "token");
    deployPredeposit(address(erc20));
    tsa = TokenizedSubAccount(address(proxy));
  }

  function testCanDepositWithdrawAndMigrate() public {
    erc20.mint(alice, 1000e18);

    vm.prank(alice);
    erc20.approve(address(tsa), 1500e18);

    // Can deposit exactly the whole cap
    vm.prank(alice);
    tsa.depositFor(alice, 200e18);

    assertEq(tsa.balanceOf(alice), 200e18);

    vm.prank(alice);
    tsa.depositFor(alice, 300e18);

    assertEq(tsa.balanceOf(alice), 500e18);

    // Cannot withdraw more than deposited
    vm.prank(alice);
    vm.expectRevert();
    tsa.withdrawTo(alice, 501e18);

    // Can withdraw some
    vm.prank(alice);
    tsa.withdrawTo(alice, 400e18);
    assertEq(tsa.balanceOf(alice), 100e18);
    assertEq(erc20.balanceOf(address(tsa)), 100e18);
    assertEq(erc20.balanceOf(alice), 900e18);
  }
}
