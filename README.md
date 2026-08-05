# ogori-geolib

On-chain point-in-polygon verification and versioned audit rule-sets for agri-food traceability.

Research artefact accompanying two manuscripts on field-evidence verification in the OGORI
traceability platform (Ogori Chain, PoA, `chainId 83333`). Everything here is reproducible: the
contracts compile from source, the benchmark script regenerates every number quoted in the papers,
and the field data it validates against is publicly readable on the OGORI block explorer.

## What is in here

| Path | Contents |
|---|---|
| `contracts/GeoLib.sol` | Fixed-point spherical geometry: haversine distance, Jordan ray-casting containment, point-to-segment distance |
| `contracts/LandRegistry.sol` | Write-once plot boundaries with per-plot distance thresholds, and in-transaction verification of a capture |
| `contracts/LensRegistry.sol` | Append-only anchor for versioned audit rule-set digests |
| `test/benchmark.js` | Gas benchmark across polygon sizes, plus cross-validation against production field events |
| `test/latency_client.mjs` | Client-side re-assessment timing (JavaScript reimplementation of the same algorithm) |
| `data/` | Plot polygons, 44 production field events, and the generated benchmark output |

The contracts are deliberately **not upgradeable**. A registered polygon cannot be mutated and the
verification logic that graded a historical event cannot be replaced after the fact, which is the
point: an evidence ledger whose grading rules can be swapped by its operator proves less than one
whose rules cannot.

## Reproducing the results

```bash
npm install
npx hardhat compile
npx hardhat run test/benchmark.js     # gas + cross-validation, writes data/benchmark_results.json
node test/latency_client.mjs          # client-side re-assessment timing
```

### Gas, measured

solc 0.8.19, optimizer enabled (200 runs), EVM target `paris`, Hardhat 2.22.15.

| Polygon vertices | `registerPlot` | `verifyEvidence` (inside) | `verifyEvidence` (outside) |
|---:|---:|---:|---:|
| 6 | 339,674 | 64,423 | 328,560 |
| 12 | 610,154 | 95,834 | 626,259 |
| 17 | 835,548 | 122,002 | 874,495 |
| 24 | 1,151,066 | 158,642 | 1,221,640 |

Cost grows linearly in the vertex count. The inside branch returns before the haversine loop runs,
which is why it costs four to eight times less than the outside branch. `LensRegistry` costs 100,957
gas to deploy and 24,518 gas per `publish`.

### Cross-validation against production

The library was run over the field events of three production lots and compared with the distances
the production platform computes off-chain in TypeScript:

| Lot | Events | Containment agreement | Mean abs. difference | Max |
|---|---:|---:|---:|---:|
| Ba Sao rice (17-vertex polygon) | 22 | 22/22 | 0.136 m | 1 m |
| NutriGreen processing (4-vertex) | 3 | 3/3 | 0.333 m | 1 m |
| **Combined** | **25** | **25/25** | **0.16 m** | **1 m** |

Sub-metre differences come from rounding in the fixed-point representation. They are two orders of
magnitude below consumer GPS error, so no event changes its label.

A third lot (Dak Lak nursery, 19 events) is excluded from the headline figure. Its plot was
reassigned mid-cycle, a supported operation for products that move between parcels, so two of its
events were originally graded against a boundary different from the one now on file. That
divergence is a finding in its own right and is discussed in the accompanying manuscripts.

## Design notes

Coordinates are signed degrees scaled by 1e7, giving roughly 1.11 cm resolution, which exceeds the
six-decimal precision that EU Regulation 2023/1115 requires.

Containment is decided in exact integer arithmetic on the scaled degree lattice using the sign of a
cross product, so no division or trigonometry enters the topological decision. Trigonometry appears
only in the distance computation, through truncated Taylor series in WAD fixed point.

The routines are exercised and validated for separations up to roughly 300 km at tropical latitudes.
The cosine series loses accuracy approaching the poles; a deployment at high latitude should swap in
an ellipsoidal formulation.

## Data provenance

The field events in `data/events_raw.csv` were read from the public OGORI lookup pages:

- Ba Sao rice lot — https://scan.ogori.vn/raw-product/600122/0xD3415B6246aa99cd6978C019583AbD5515d6D303
- NutriGreen processing lot — https://scan.ogori.vn/raw-product/600070/0x8334050Cdaecdddc926A16169e5e81533798306f
- Dak Lak nursery lot — https://scan.ogori.vn/raw-product/600067/0x5027faAC1fe6C9a448bFC35fE3242E365488cF9d

## Status

Research prototype. The OGORI production deployment currently performs the spatial classification
off-chain; the contracts here implement and measure the on-chain alternative. They have not been
audited and are not deployed to a production network.

## Citation

Manuscripts are under review. Please cite this repository until they appear.

## License

MIT — see `LICENSE`.
