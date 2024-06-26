pragma solidity ^0.8.18;

import "../TSATestUtils.sol";
/*
Deposits:
- ✅multiple deposits can be processed (dont have to be sequential)
- ✅depositors get different amounts of shares based on changes to NAV
- ✅deposits are blocked when there is a liquidation
- ✅deposits cannot be processed if they are already processed
- ✅deposits below the minimum are rejected
- ✅deposits cannot be queued if cap is exceeded
- ✅deposits CAN be processed if cap is exceeded
- ✅deposits will be scaled by the depositScale
- any deposit will collect fees correctly (before totalSupply is changed)
*/

contract CCTSA_BaseTSA_DepositTests is CCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToCCTSA("weth");
    setupCCTSA();
  }

  function testMessyDeposits() public {
    markets["weth"].erc20.mint(address(this), 10e18);
    markets["weth"].erc20.approve(address(tsa), 10e18);
    uint depositId = tsa.initiateDeposit(1e18, address(this));
    tsa.processDeposit(depositId);
    assertEq(tsa.balanceOf(address(this)), 1e18);
    _executeDeposit(0.8e18);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), 0.2e18);
    assertEq(subAccounts.getBalance(tsa.subAccount(), markets["weth"].base, 0), 0.8e18);
    depositId = tsa.initiateDeposit(1e18, address(this));
    tsa.processDeposit(depositId);
    assertEq(tsa.balanceOf(address(this)), 2e18);
    tsa.requestWithdrawal(0.25e18);
    assertEq(tsa.balanceOf(address(this)), 1.75e18);
    assertEq(tsa.totalPendingWithdrawals(), 0.25e18);
    vm.warp(block.timestamp + 10 minutes + 1);
    tsa.processWithdrawalRequests(1);
    assertEq(tsa.balanceOf(address(this)), 1.75e18);
  }

  function testDepositsAreProcessedSequentially() public {
    // Mint some tokens and approve the TSA contract to spend them
    uint depositAmount = 1e18;
    uint numDeposits = 5;
    markets["weth"].erc20.mint(address(this), depositAmount * numDeposits);
    markets["weth"].erc20.approve(address(tsa), depositAmount * numDeposits);

    uint[] memory depositIds = new uint[](numDeposits);
    // Initiate and process multiple deposits
    for (uint i = 0; i < numDeposits; i++) {
      depositIds[i] = tsa.initiateDeposit(depositAmount, address(this));
    }

    // Check state is as expected
    assertEq(tsa.balanceOf(address(this)), 0);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), depositAmount * numDeposits);

    for (uint i = 0; i < numDeposits; i++) {
      BaseTSA.DepositRequest memory depReq = tsa.queuedDeposit(depositIds[i]);
      assertEq(depReq.amountDepositAsset, depositAmount);
      assertEq(depReq.recipient, address(this));
      assertEq(depReq.sharesReceived, 0);
    }

    // Process all
    tsa.processDeposits(depositIds);

    for (uint i = 0; i < numDeposits; i++) {
      BaseTSA.DepositRequest memory depReq = tsa.queuedDeposit(depositIds[i]);
      // There are no partial deposits, so amountDepositAsset doesn't need to change
      assertEq(depReq.amountDepositAsset, depositAmount);
      assertEq(depReq.recipient, address(this));
      assertEq(depReq.sharesReceived, depositAmount);
    }

    // Check state is as expected
    assertEq(tsa.balanceOf(address(this)), depositAmount * numDeposits);
  }

  function testDepositsGetDifferentAmountsOfSharesBasedOnChangesToNAV() public {
    // Mint some tokens and approve the TSA contract to spend them
    uint depositAmount = 1e18;
    uint numDeposits = 5;
    markets["weth"].erc20.mint(address(this), depositAmount * numDeposits);
    markets["weth"].erc20.approve(address(tsa), depositAmount * numDeposits);

    uint[] memory depositIds = new uint[](numDeposits);
    // Initiate and process multiple deposits
    for (uint i = 0; i < numDeposits; i++) {
      depositIds[i] = tsa.initiateDeposit(depositAmount, address(this));
    }

    // Check state is as expected
    assertEq(tsa.balanceOf(address(this)), 0);
    assertEq(tsa.totalPendingDeposits(), depositAmount * numDeposits);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), depositAmount * numDeposits);
    assertEq(tsa.getNumShares(1e18), 1e18);
    assertEq(tsa.getSharesValue(1e18), 1e18);

    for (uint i = 0; i < numDeposits; i++) {
      BaseTSA.DepositRequest memory depReq = tsa.queuedDeposit(depositIds[i]);
      assertEq(depReq.amountDepositAsset, depositAmount);
      assertEq(depReq.recipient, address(this));
      assertEq(depReq.sharesReceived, 0);
    }

    // Process 2
    tsa.processDeposit(depositIds[1]);
    tsa.processDeposit(depositIds[0]);

    for (uint i = 0; i < 2; i++) {
      BaseTSA.DepositRequest memory depReq = tsa.queuedDeposit(depositIds[i]);
      // There are no partial deposits, so amountDepositAsset doesn't need to change
      assertEq(depReq.amountDepositAsset, depositAmount);
      assertEq(depReq.recipient, address(this));
      assertEq(depReq.sharesReceived, depositAmount);
    }

    // Get 2 shares
    assertEq(tsa.balanceOf(address(this)), depositAmount * 2, "Share balance of depositor");
    assertEq(tsa.totalSupply(), depositAmount * 2, "TSA total supply");
    assertEq(tsa.totalPendingDeposits(), depositAmount * 3, "Total pending deposits");
    assertEq(tsa.getNumShares(1e18), 1e18);
    assertEq(tsa.getSharesValue(1e18), 1e18);

    // Double the value of the pool
    markets["weth"].erc20.mint(address(tsa), depositAmount * 2);

    assertEq(tsa.getNumShares(1e18), 0.5e18);
    assertEq(tsa.getSharesValue(1e18), 2e18);

    tsa.processDeposit(depositIds[3]);
    tsa.processDeposit(depositIds[2]);

    for (uint i = 0; i < 2; i++) {
      BaseTSA.DepositRequest memory depReq = tsa.queuedDeposit(depositIds[i + 2]);
      // There are no partial deposits, so amountDepositAsset doesn't need to change
      assertEq(depReq.amountDepositAsset, depositAmount, "Deposit amount");
      assertEq(depReq.recipient, address(this));
      assertEq(depReq.sharesReceived, depositAmount / 2, "Shares received");
    }

    // Get 1 more share, as each share is now 2 weth worth
    assertEq(tsa.balanceOf(address(this)), depositAmount * 3, "Share balance");

    // Double the value of the pool (has 6)
    markets["weth"].erc20.mint(address(tsa), depositAmount * 6);

    tsa.processDeposit(depositIds[4]);

    {
      BaseTSA.DepositRequest memory depReq = tsa.queuedDeposit(depositIds[4]);
      assertEq(depReq.sharesReceived, depositAmount / 4, "Shares received");
    }

    // Get 0.25 more shares, as each share is now 4 weth worth (3.25 total)
    assertEq(tsa.balanceOf(address(this)), depositAmount * 3.25e2 / 1e2, "Share balance");
  }

  function testDepositsAreBlockedWhenThereIsALiquidation() public {
    // Mint some tokens and approve the TSA contract to spend them
    uint depositAmount = 1e18;
    markets["weth"].erc20.mint(address(this), depositAmount);
    markets["weth"].erc20.approve(address(tsa), depositAmount);

    // Initiate a deposit
    uint depositId = tsa.initiateDeposit(depositAmount, address(this));

    // Check state is as expected
    assertEq(tsa.balanceOf(address(this)), 0);
    assertEq(tsa.totalPendingDeposits(), depositAmount);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), depositAmount);

    // Create an insolvent auction
    uint liquidationId = _createInsolventAuction();

    // Try to process the deposit
    assertEq(tsa.isBlocked(), true);
    vm.expectRevert(BaseTSA.BTSA_Blocked.selector);
    tsa.processDeposit(depositId);

    // Check state is as expected
    assertEq(tsa.balanceOf(address(this)), 0);
    assertEq(tsa.totalPendingDeposits(), depositAmount);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), depositAmount);
  }

  function testDepositsCannotBeProcessedIfTheyAreAlreadyProcessed() public {
    // Mint some tokens and approve the TSA contract to spend them
    uint depositAmount = 1e18;
    markets["weth"].erc20.mint(address(this), depositAmount);
    markets["weth"].erc20.approve(address(tsa), depositAmount);

    // Initiate a deposit
    uint depositId = tsa.initiateDeposit(depositAmount, address(this));

    // Check state is as expected
    assertEq(tsa.balanceOf(address(this)), 0);
    assertEq(tsa.totalPendingDeposits(), depositAmount);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), depositAmount);

    // Process the deposit
    tsa.processDeposit(depositId);

    // Check state is as expected
    assertEq(tsa.balanceOf(address(this)), depositAmount);
    assertEq(tsa.totalPendingDeposits(), 0);
    assertEq(markets["weth"].erc20.balanceOf(address(tsa)), depositAmount);

    // Try to process the deposit again
    vm.expectRevert(BaseTSA.BTSA_DepositAlreadyProcessed.selector);
    tsa.processDeposit(depositId);
  }

  function testDepositsQueueFailureReasons() public {
    // Mint some tokens and approve the TSA contract to spend them
    uint depositAmount = 1e18;
    markets["weth"].erc20.mint(address(this), depositAmount);
    markets["weth"].erc20.approve(address(tsa), depositAmount);

    BaseTSA.TSAParams memory params = tsa.getTSAParams();

    params.minDepositValue = 1.01e18;
    tsa.setTSAParams(params);

    vm.expectRevert(BaseTSA.BTSA_DepositBelowMinimum.selector);
    tsa.initiateDeposit(1e18, address(this));

    params.minDepositValue = 0;
    params.depositCap = 0.99e18;
    tsa.setTSAParams(params);

    vm.expectRevert(BaseTSA.BTSA_DepositCapExceeded.selector);
    tsa.initiateDeposit(1e18, address(this));

    params.depositCap = 1e18;
    tsa.setTSAParams(params);
    uint depositId = tsa.initiateDeposit(1e18, address(this));

    // Can process even if cap is lower

    params.depositCap = 0;
    tsa.setTSAParams(params);
    tsa.processDeposit(depositId);
  }
}
