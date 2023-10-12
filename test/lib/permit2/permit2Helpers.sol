// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "@mgv/forge-std/Test.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {PermitSignature} from "lib/permit2/test/utils/PermitSignature.sol";

contract PermitSignatureExposer is PermitSignature {
  function getPermitSignatureExternal(
    IAllowanceTransfer.PermitSingle memory permit,
    uint privateKey,
    bytes32 domainSeparator
  ) external pure returns (bytes memory sig) {
    return getPermitSignature(permit, privateKey, domainSeparator);
  }
}

contract Permit2Helpers is Test {
  PermitSignatureExposer permitSignature = new PermitSignatureExposer();

  function getPermitTransferSignatureWithSpecifiedAddress(
    ISignatureTransfer.PermitTransferFrom memory permit,
    uint privateKey,
    bytes32 domainSeparator,
    address addr
  ) internal view returns (bytes memory sig) {
    bytes32 tokenPermissions = keccak256(abi.encode(permitSignature._TOKEN_PERMISSIONS_TYPEHASH(), permit.permitted));
    bytes32 msgHash = keccak256(
      abi.encodePacked(
        "\x19\x01",
        domainSeparator,
        keccak256(
          abi.encode(
            permitSignature._PERMIT_TRANSFER_FROM_TYPEHASH(), tokenPermissions, addr, permit.nonce, permit.deadline
          )
        )
      )
    );

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
    return bytes.concat(r, s, bytes1(v));
  }

  function getPermitSignature(IAllowanceTransfer.PermitSingle memory permit, uint privateKey, bytes32 domainSeparator)
    internal
    view
    returns (bytes memory sig)
  {
    return permitSignature.getPermitSignatureExternal(permit, privateKey, domainSeparator);
  }

  function getPermitTransferFrom(address token, uint amount, uint nonce, uint deadline)
    internal
    pure
    returns (ISignatureTransfer.PermitTransferFrom memory)
  {
    return ISignatureTransfer.PermitTransferFrom({
      permitted: ISignatureTransfer.TokenPermissions({token: token, amount: amount}),
      nonce: nonce,
      deadline: deadline
    });
  }

  function getPermit(address token, uint160 amount, uint48 expiration, uint48 nonce, address spender)
    internal
    pure
    returns (IAllowanceTransfer.PermitSingle memory)
  {
    IAllowanceTransfer.PermitDetails memory permitDetails =
      IAllowanceTransfer.PermitDetails({token: address(token), amount: amount, expiration: expiration, nonce: nonce});
    IAllowanceTransfer.PermitSingle memory permit =
      IAllowanceTransfer.PermitSingle({details: permitDetails, spender: address(spender), sigDeadline: expiration});

    return permit;
  }
}
