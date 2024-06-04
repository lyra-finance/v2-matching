pragma solidity ^0.8.18;

import "../TSATestUtils.sol";
/*
Tests for TSA signing
- ✅only signers can sign
- ✅only signers can revoke
- ✅only signers can revoke action signatures
- ✅signatures are stored correctly
- ✅signatures can be revoked
- ✅signatures can be revoked for actions
- ✅signatures can be verified
*/

contract LRTCCTSA_BaseOnChainSigningTSATests is LRTCCTSATestUtils {
  function setUp() public override {
    super.setUp();
    deployPredeposit(address(0));
    upgradeToLRTCCTSA("weth");
    setupLRTCCTSA();
    tsa = LRTCCTSA(address(proxy));
  }

  function testCanSetSigner() public {
    tsa.setSigner(address(this), true);
    assertTrue(tsa.isSigner(address(this)));
    tsa.setSigner(address(this), false);
    assertTrue(!tsa.isSigner(address(this)));
  }

  function testCanSetSignaturesEnabled() public {
    tsa.setSignaturesDisabled(true);
    assertTrue(tsa.signaturesDisabled());
    tsa.setSignaturesDisabled(false);
    assertTrue(!tsa.signaturesDisabled());
  }

  function testCanSignActionData() public {
    tsa.setSigner(address(this), true);
    IActionVerifier.Action memory action = _createDepositAction(1e18);
    tsa.signActionData(action);

    assertTrue(tsa.isActionSigned(action));
  }

  function testCanRevokeSignature() public {
    tsa.setSigner(address(this), true);
    IActionVerifier.Action memory action = _createDepositAction(1e18);
    tsa.signActionData(action);

    assertTrue(tsa.isActionSigned(action));

    tsa.revokeActionSignature(action);

    assertTrue(!tsa.isActionSigned(action));
  }

  function testCanRevokeSignatureWithHash() public {
    tsa.setSigner(address(this), true);
    IActionVerifier.Action memory action = _createDepositAction(1e18);
    tsa.signActionData(action);

    assertTrue(tsa.isActionSigned(action));

    bytes32 hash = tsa.getActionTypedDataHash(action);
    tsa.revokeSignature(hash);

    assertTrue(!tsa.isActionSigned(action));
  }

  function testOnlySignerCanSign() public {
    IActionVerifier.Action memory action = _createDepositAction(1e18);
    vm.expectRevert(BaseOnChainSigningTSA.BOCST_OnlySigner.selector);
    tsa.signActionData(action);
  }

  function testOnlySignerCanRevoke() public {
    IActionVerifier.Action memory action = _createDepositAction(1e18);
    vm.expectRevert(BaseOnChainSigningTSA.BOCST_OnlySigner.selector);
    tsa.revokeActionSignature(action);

    bytes32 hash = tsa.getActionTypedDataHash(action);
    vm.expectRevert(BaseOnChainSigningTSA.BOCST_OnlySigner.selector);
    tsa.revokeSignature(hash);
  }
}