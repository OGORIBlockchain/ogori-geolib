// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title LensRegistry
 * @notice Append-only anchor for versioned audit rule-sets ("lenses").
 * @dev The contract stores no rule content. Publishing a lens emits the SHA-256 digest
 *      of the canonicalised rule-set document, which makes a classification verdict
 *      reproducible: an auditor fetches the document by digest, recomputes the hash, and
 *      confirms the anchoring block. Because nothing is written to storage, a published
 *      lens cannot be withdrawn or silently edited, only superseded by a later version.
 *
 *      Issuer authorisation is deliberately left outside the contract. Clients verify
 *      the `issuer` field against their own trust list, which lets a regulator, a
 *      certification body and a producer each maintain independent lens namespaces
 *      without a shared on-chain gatekeeper.
 */
contract LensRegistry {
    event RuleSetPublished(
        bytes32 indexed lensId,
        bytes32 indexed digest,
        address indexed issuer,
        uint64 timestamp
    );

    /// @notice Anchor a rule-set digest. Emits only; no storage is mutated.
    function publish(bytes32 lensId, bytes32 digest) external {
        emit RuleSetPublished(lensId, digest, msg.sender, uint64(block.timestamp));
    }
}
