// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Sig} from "./Utils.sol";
import {Settlement} from "./Settlement.sol";

// IDKit proof verification happens on the backend. This contract verifies its
// short-lived, report-scoped authorization and the on-chain winning position.
contract Reputation {
    Settlement public immutable settlement;
    address public immutable identitySigner;
    mapping(uint256 => mapping(address => bool)) public hasBadge;
    mapping(uint256 => mapping(bytes32 => bool)) public usedScopedNullifier;
    mapping(address => mapping(uint256 => bool)) public usedNonce;
    event BadgeMinted(uint256 indexed reportId, address indexed recipient, bytes32 scopedNullifier);

    constructor(Settlement settlement_, address signer_) {
        require(address(settlement_) != address(0) && signer_ != address(0));
        settlement = settlement_;
        identitySigner = signer_;
    }

    function authorizationDigest(
        uint256 reportId,
        address recipient,
        bytes32 scopedNullifier,
        uint256 nonce,
        uint64 expiry
    ) public view returns (bytes32) {
        return Sig.ethSigned(
            keccak256(abi.encode(block.chainid, address(this), reportId, recipient, scopedNullifier, nonce, expiry))
        );
    }

    function claimWinnerREP(
        uint256 reportId,
        address recipient,
        bytes32 scopedNullifier,
        uint256 nonce,
        uint64 expiry,
        bytes calldata signature
    ) external {
        require(recipient != address(0) && scopedNullifier != 0 && block.timestamp <= expiry, "CLAIM");
        require(!hasBadge[reportId][recipient] && !usedScopedNullifier[reportId][scopedNullifier], "ALREADY_CLAIMED");
        require(!usedNonce[identitySigner][nonce], "NONCE");
        require(settlement.eligibleWinner(reportId, recipient), "INELIGIBLE");
        require(
            Sig.recover(authorizationDigest(reportId, recipient, scopedNullifier, nonce, expiry), signature)
                == identitySigner,
            "SIGNER"
        );
        usedNonce[identitySigner][nonce] = true;
        usedScopedNullifier[reportId][scopedNullifier] = true;
        hasBadge[reportId][recipient] = true;
        emit BadgeMinted(reportId, recipient, scopedNullifier);
    }

    function balanceOf(address account, uint256 reportId) external view returns (uint256) {
        return hasBadge[reportId][account] ? 1 : 0;
    }
}
