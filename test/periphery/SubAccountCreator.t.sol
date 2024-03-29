// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.18;

import {IManager} from "v2-core/src/interfaces/IManager.sol";

import {MatchingBase} from "test/shared/MatchingBase.t.sol";
import {SubAccountCreator} from "src/periphery/SubAccountCreator.sol";

contract SubAccountCreatorTest is MatchingBase {
  SubAccountCreator public creator;

  function setUp() public override {
    super.setUp();

    creator = new SubAccountCreator(subAccounts, matching);
  }

  function testCanCreateWithInitDeposit() public {
    uint amount = 100e6;
    usdc.mint(cam, amount);

    vm.startPrank(cam);
    usdc.approve(address(creator), type(uint).max);

    uint accId = creator.createAndDepositSubAccount(cash, amount, pmrm);

    assertEq(matching.subAccountToOwner(accId), cam);
    assertEq(subAccounts.getBalance(accId, cash, 0), int(amount));
    vm.stopPrank();
  }

  function testCanCreateWithNoUSDC() public {
    vm.startPrank(cam);
    uint accId = creator.createAndDepositSubAccount(cash, 0, pmrm);
    assertEq(matching.subAccountToOwner(accId), cam);
  }

  function testCanCreateWithBaseAsset() public {
    uint amount = 100e18;
    weth.mint(cam, amount);

    vm.startPrank(cam);
    weth.approve(address(creator), type(uint).max);
    uint accId = creator.createAndDepositSubAccount(baseAsset, amount, pmrm);
    assertEq(matching.subAccountToOwner(accId), cam);
    assertEq(subAccounts.getBalance(accId, baseAsset, 0), int(amount));
  }
}
