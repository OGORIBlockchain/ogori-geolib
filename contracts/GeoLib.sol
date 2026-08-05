// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title GeoLib
 * @notice Fixed-point spherical geometry for on-chain field-evidence verification.
 * @dev Coordinates are signed degrees scaled by 1e7 (COORD_SCALE), giving ~1.11 cm
 *      resolution at the equator, which exceeds the six-decimal precision required by
 *      EU Regulation 2023/1115. Internal trigonometry uses WAD (1e18) fixed point with
 *      truncated Taylor expansions; see the accompanying paper for the error analysis.
 *
 *      Validity range: the haversine routine is exercised and validated for separations
 *      up to ~300 km, which covers plot-scale verification and the gross-displacement
 *      cases observed in production. It is not intended for antipodal geometry.
 */
library GeoLib {
    int256 internal constant WAD = 1e18;
    int256 internal constant COORD_SCALE = 1e7;
    /// @dev pi scaled by WAD
    int256 internal constant PI = 3141592653589793238;
    /// @dev Mean Earth radius (WGS-84 authalic sphere), metres
    int256 internal constant EARTH_R = 6371008;
    /// @dev degE7 -> radians(WAD) divisor: 180 * COORD_SCALE
    int256 internal constant DEG_DIV = 180 * COORD_SCALE;

    struct Point {
        int256 lat; // degrees * 1e7
        int256 lon; // degrees * 1e7
    }

    // ---------------------------------------------------------------- fixed point

    function wmul(int256 a, int256 b) internal pure returns (int256) {
        return (a * b) / WAD;
    }

    function wdiv(int256 a, int256 b) internal pure returns (int256) {
        return (a * WAD) / b;
    }

    /// @notice Babylonian square root on WAD fixed point.
    function wsqrt(int256 x) internal pure returns (int256) {
        if (x <= 0) return 0;
        // scale into integer domain: sqrt(x/WAD) * WAD = sqrt(x * WAD)
        uint256 n = uint256(x) * uint256(WAD);
        uint256 z = (n + 1) / 2;
        uint256 y = n;
        while (z < y) {
            y = z;
            z = (n / z + z) / 2;
        }
        return int256(y);
    }

    /// @notice sin(x) for x in radians (WAD), |x| <= pi. Truncated Taylor, 7 terms.
    function sin(int256 x) internal pure returns (int256) {
        int256 x2 = wmul(x, x);
        int256 term = x; // x
        int256 acc = term;
        term = -wmul(term, x2) / 6; // -x^3/3!
        acc += term;
        term = -wmul(term, x2) / 20; // +x^5/5!
        acc += term;
        term = -wmul(term, x2) / 42; // -x^7/7!
        acc += term;
        term = -wmul(term, x2) / 72; // +x^9/9!
        acc += term;
        term = -wmul(term, x2) / 110; // -x^11/11!
        acc += term;
        term = -wmul(term, x2) / 156; // +x^13/13!
        acc += term;
        return acc;
    }

    /// @notice cos(x) for x in radians (WAD), |x| <= pi/2. Truncated Taylor, 7 terms.
    function cos(int256 x) internal pure returns (int256) {
        int256 x2 = wmul(x, x);
        int256 term = WAD; // 1
        int256 acc = term;
        term = -wmul(term, x2) / 2; // -x^2/2!
        acc += term;
        term = -wmul(term, x2) / 12; // +x^4/4!
        acc += term;
        term = -wmul(term, x2) / 30; // -x^6/6!
        acc += term;
        term = -wmul(term, x2) / 56; // +x^8/8!
        acc += term;
        term = -wmul(term, x2) / 90; // -x^10/10!
        acc += term;
        term = -wmul(term, x2) / 132; // +x^12/12!
        acc += term;
        return acc;
    }

    /// @notice asin(x) for |x| <= 0.5 (WAD). Series to x^7; sufficient for separations
    ///         well beyond the validated 300 km range.
    function asin(int256 x) internal pure returns (int256) {
        int256 x2 = wmul(x, x);
        int256 x3 = wmul(x2, x);
        int256 x5 = wmul(x3, x2);
        int256 x7 = wmul(x5, x2);
        return x + x3 / 6 + (3 * x5) / 40 + (15 * x7) / 336;
    }

    function degE7ToRad(int256 degE7) internal pure returns (int256) {
        return (degE7 * PI) / DEG_DIV;
    }

    // ---------------------------------------------------------------- distance

    /**
     * @notice Great-circle distance between two coordinates, in whole metres.
     * @dev a = sin^2(dPhi/2) + cos(phi1)cos(phi2)sin^2(dLambda/2); d = 2R*asin(sqrt(a)).
     */
    function haversine(Point memory p1, Point memory p2) internal pure returns (uint256) {
        int256 phi1 = degE7ToRad(p1.lat);
        int256 phi2 = degE7ToRad(p2.lat);
        int256 dPhiHalf = degE7ToRad(p2.lat - p1.lat) / 2;
        int256 dLamHalf = degE7ToRad(p2.lon - p1.lon) / 2;

        int256 sPhi = sin(dPhiHalf);
        int256 sLam = sin(dLamHalf);

        int256 a = wmul(sPhi, sPhi) + wmul(wmul(cos(phi1), cos(phi2)), wmul(sLam, sLam));
        if (a <= 0) return 0;

        int256 c = 2 * asin(wsqrt(a));
        int256 d = (c * EARTH_R) / WAD;
        return d < 0 ? uint256(-d) : uint256(d);
    }

    /// @notice Metres per degree of latitude (WAD-free, whole metres * 1e7 scale factor).
    function metresPerDegLat() internal pure returns (int256) {
        // pi * R / 180, in metres per degree
        return (PI * EARTH_R) / (180 * WAD);
    }

    /**
     * @notice Shortest distance in metres from `p` to segment `a`-`b`.
     * @dev The closest point is located by planar projection into a local
     *      equirectangular frame centred on `p`, then the reported distance is the
     *      great-circle distance from `p` to that interpolated point. The projection is
     *      used only to find the parameter t, so the returned magnitude stays spherical.
     */
    function distanceToSegment(
        Point memory p,
        Point memory a,
        Point memory b
    ) internal pure returns (uint256) {
        int256 t = _closestParam(p, a, b);
        return
            haversine(
                p,
                Point({
                    lat: a.lat + ((b.lat - a.lat) * t) / WAD,
                    lon: a.lon + ((b.lon - a.lon) * t) / WAD
                })
            );
    }

    /// @dev Parameter t in [0, WAD] of the point on segment a-b closest to p, found in a
    ///      local equirectangular frame centred on p.
    function _closestParam(
        Point memory p,
        Point memory a,
        Point memory b
    ) private pure returns (int256 t) {
        int256 mLat = metresPerDegLat();
        int256 mLon = (mLat * cos(degE7ToRad(p.lat))) / WAD;

        // planar offsets in metres, origin at p
        int256 ax = ((a.lon - p.lon) * mLon) / COORD_SCALE;
        int256 ay = ((a.lat - p.lat) * mLat) / COORD_SCALE;
        int256 dx = (((b.lon - p.lon) * mLon) / COORD_SCALE) - ax;
        int256 dy = (((b.lat - p.lat) * mLat) / COORD_SCALE) - ay;

        int256 denom = dx * dx + dy * dy;
        if (denom == 0) return 0;

        // t = dot(p - a, b - a) / |b - a|^2, with p at the origin
        t = (((-ax) * dx + (-ay) * dy) * WAD) / denom;
        if (t < 0) return 0;
        if (t > WAD) return WAD;
    }

    // ---------------------------------------------------------------- topology

    /**
     * @notice Jordan ray-casting containment test.
     * @dev Performed in exact integer arithmetic on the scaled degree lattice: an
     *      eastward ray is cast from `p` and edge crossings are counted via the sign of
     *      a cross product, so no division or trigonometry enters the topological
     *      decision. Odd crossing count means the point lies inside.
     */
    function contains(Point memory p, Point[] memory poly) internal pure returns (bool) {
        uint256 n = poly.length;
        bool inside = false;
        for (uint256 i = 0; i < n; i++) {
            Point memory a = poly[i];
            Point memory b = poly[(i + 1) % n];

            bool straddles = (a.lon > p.lon) != (b.lon > p.lon);
            if (!straddles) continue;

            // sign of the cross product decides which side of edge (a,b) p falls on
            int256 cross = (b.lat - a.lat) * (p.lon - a.lon) - (b.lon - a.lon) * (p.lat - a.lat);
            if (b.lon > a.lon) {
                if (cross > 0) inside = !inside;
            } else {
                if (cross < 0) inside = !inside;
            }
        }
        return inside;
    }

    /**
     * @notice Containment test plus distance to the boundary when outside.
     * @return inside true when `p` lies within `poly`
     * @return distance 0 when inside, otherwise metres to the nearest boundary point
     */
    function locate(
        Point memory p,
        Point[] memory poly
    ) internal pure returns (bool inside, uint256 distance) {
        inside = contains(p, poly);
        if (inside) return (true, 0);

        uint256 n = poly.length;
        uint256 best = type(uint256).max;
        for (uint256 i = 0; i < n; i++) {
            uint256 d = distanceToSegment(p, poly[i], poly[(i + 1) % n]);
            if (d < best) best = d;
        }
        return (false, best);
    }
}
