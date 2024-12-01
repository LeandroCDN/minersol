// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureTransfer} from "./interfaces/ISignatureTransfer.sol";

contract Miner {
    ISignatureTransfer public permit2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // Deposit some amount of an ERC20 token from the caller
    // into this contract using Permit2.
    function depositERC20(
        IERC20 token,
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) external {
        permit2.permitTransferFrom(permit, transferDetails, msg.sender , signature);
    }

}