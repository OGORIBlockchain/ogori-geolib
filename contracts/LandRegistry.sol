// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GeoLib.sol";

/**
 * @title LandRegistry
 * @notice Immutable registry of cultivation-plot boundaries with per-plot distance
 *         thresholds, plus in-transaction spatial verification of field evidence.
 * @dev Plot geometry is write-once: `registerPlot` reverts for an identifier that is
 *      already occupied and no function can mutate an existing vertex array. The
 *      contract is deliberately non-upgradeable, so the verification logic that graded
 *      a historical event cannot be altered after the fact.
 *
 *      The threshold pair carried alongside each plot is the operator's default display
 *      lens. It is emitted with every verification so that downstream auditors can
 *      reproduce the label, but it never gates acceptance: an event outside the
 *      thresholds is still recorded, only labelled differently.
 */
contract LandRegistry {
    /// @notice Distance tier assigned to a capture, reflecting positioning accuracy
    ///         relative to the registered plot rather than an accept/reject verdict.
    enum Tier {
        GREEN, // within the plot, or outside by no more than greenMaxMetres
        YELLOW, // beyond GREEN but still explainable by ordinary GPS drift
        RED // beyond any plausible positioning error
    }

    struct Plot {
        bool exists;
        uint16 greenMaxMetres;
        uint16 yellowMaxMetres;
        GeoLib.Point[] vertices;
    }

    mapping(bytes32 => Plot) private _plots;

    event PlotRegistered(
        bytes32 indexed plotId,
        uint256 vertexCount,
        uint16 greenMaxMetres,
        uint16 yellowMaxMetres
    );

    event EvidenceVerified(
        bytes32 indexed plotId,
        bytes32 indexed mediaHash,
        int256 lat,
        int256 lon,
        bool inside,
        uint256 distanceMetres,
        Tier tier
    );

    error PlotAlreadyExists(bytes32 plotId);
    error PlotUnknown(bytes32 plotId);
    error PolygonTooSmall(uint256 vertexCount);
    error ThresholdsNotOrdered(uint16 greenMaxMetres, uint16 yellowMaxMetres);

    /**
     * @notice Register a plot boundary. Write-once per identifier.
     * @param plotId caller-chosen identifier, typically keccak256 of the off-chain plot key
     * @param vertices boundary ring in degrees scaled by 1e7; the ring must not repeat
     *                 the first vertex at the end
     */
    function registerPlot(
        bytes32 plotId,
        GeoLib.Point[] calldata vertices,
        uint16 greenMaxMetres,
        uint16 yellowMaxMetres
    ) external {
        if (_plots[plotId].exists) revert PlotAlreadyExists(plotId);
        if (vertices.length < 3) revert PolygonTooSmall(vertices.length);
        if (greenMaxMetres > yellowMaxMetres) {
            revert ThresholdsNotOrdered(greenMaxMetres, yellowMaxMetres);
        }

        Plot storage p = _plots[plotId];
        p.exists = true;
        p.greenMaxMetres = greenMaxMetres;
        p.yellowMaxMetres = yellowMaxMetres;
        for (uint256 i = 0; i < vertices.length; i++) {
            p.vertices.push(vertices[i]);
        }

        emit PlotRegistered(plotId, vertices.length, greenMaxMetres, yellowMaxMetres);
    }

    /**
     * @notice Verify a capture against a registered plot and record the outcome.
     * @dev State-changing so that the spatial decision is anchored in the same
     *      transaction that commits the evidence reference. Returns the tier for
     *      callers that compose this into a larger write.
     */
    function verifyEvidence(
        bytes32 plotId,
        bytes32 mediaHash,
        int256 lat,
        int256 lon
    ) external returns (bool inside, uint256 distanceMetres, Tier tier) {
        Plot storage p = _plots[plotId];
        if (!p.exists) revert PlotUnknown(plotId);

        (inside, distanceMetres) = _locate(p, lat, lon);
        tier = _grade(distanceMetres, p.greenMaxMetres, p.yellowMaxMetres);

        emit EvidenceVerified(plotId, mediaHash, lat, lon, inside, distanceMetres, tier);
    }

    /// @notice Read-only variant for off-chain re-evaluation and gas comparison.
    function locate(
        bytes32 plotId,
        int256 lat,
        int256 lon
    ) external view returns (bool inside, uint256 distanceMetres, Tier tier) {
        Plot storage p = _plots[plotId];
        if (!p.exists) revert PlotUnknown(plotId);
        (inside, distanceMetres) = _locate(p, lat, lon);
        tier = _grade(distanceMetres, p.greenMaxMetres, p.yellowMaxMetres);
    }

    function getPolygon(bytes32 plotId) external view returns (GeoLib.Point[] memory) {
        if (!_plots[plotId].exists) revert PlotUnknown(plotId);
        return _plots[plotId].vertices;
    }

    function getThresholds(
        bytes32 plotId
    ) external view returns (uint16 greenMaxMetres, uint16 yellowMaxMetres) {
        Plot storage p = _plots[plotId];
        if (!p.exists) revert PlotUnknown(plotId);
        return (p.greenMaxMetres, p.yellowMaxMetres);
    }

    function vertexCount(bytes32 plotId) external view returns (uint256) {
        return _plots[plotId].vertices.length;
    }

    // ---------------------------------------------------------------- internals

    function _locate(
        Plot storage p,
        int256 lat,
        int256 lon
    ) private view returns (bool inside, uint256 distanceMetres) {
        uint256 n = p.vertices.length;
        GeoLib.Point[] memory poly = new GeoLib.Point[](n);
        for (uint256 i = 0; i < n; i++) {
            poly[i] = p.vertices[i];
        }
        return GeoLib.locate(GeoLib.Point({lat: lat, lon: lon}), poly);
    }

    function _grade(
        uint256 distanceMetres,
        uint16 greenMaxMetres,
        uint16 yellowMaxMetres
    ) private pure returns (Tier) {
        if (distanceMetres <= greenMaxMetres) return Tier.GREEN;
        if (distanceMetres <= yellowMaxMetres) return Tier.YELLOW;
        return Tier.RED;
    }
}
