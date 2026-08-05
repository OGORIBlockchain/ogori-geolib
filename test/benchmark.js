// Gas benchmark and field-data validation for the on-chain geometry layer.
// Run: npx hardhat run test/benchmark.js
const fs = require("fs");
const path = require("path");
const hre = require("hardhat");

const E7 = 1e7;
const DATA = path.join(__dirname, "..", "..", "data");

const toE7 = (deg) => BigInt(Math.round(deg * E7));
// polygons.json stores [lon, lat]; drop the repeated closing vertex
const ringToPoints = (verts) => {
  const v = verts.slice();
  const first = v[0];
  const last = v[v.length - 1];
  if (first[0] === last[0] && first[1] === last[1]) v.pop();
  return v.map(([lon, lat]) => ({ lat: toE7(lat), lon: toE7(lon) }));
};

// Synthetic regular polygons for the vertex-count sweep, centred on the Ba Sao plot.
function regularPolygon(n, centreLat, centreLon, radiusMetres) {
  const mPerDegLat = 111194.9266;
  const mPerDegLon = mPerDegLat * Math.cos((centreLat * Math.PI) / 180);
  const pts = [];
  for (let i = 0; i < n; i++) {
    const th = (2 * Math.PI * i) / n;
    pts.push({
      lat: toE7(centreLat + (radiusMetres * Math.sin(th)) / mPerDegLat),
      lon: toE7(centreLon + (radiusMetres * Math.cos(th)) / mPerDegLon),
    });
  }
  return pts;
}

function readEvents() {
  const csv = fs.readFileSync(path.join(DATA, "events_raw.csv"), "utf8").trim().split("\n");
  const head = csv[0].split(",");
  return csv.slice(1).map((line) => {
    // tx_hash is last and may contain no commas; simple split is safe for this file
    const cols = line.split(",");
    const row = {};
    head.forEach((h, i) => (row[h] = cols[i]));
    return row;
  });
}

async function main() {
  const id = (s) => hre.ethers.keccak256(hre.ethers.toUtf8Bytes(s));
  const Reg = await hre.ethers.getContractFactory("LandRegistry");
  const reg = await Reg.deploy();
  await reg.waitForDeployment();

  const deployRc = await hre.ethers.provider.getTransactionReceipt(
    reg.deploymentTransaction().hash
  );

  const results = { deployGas: deployRc.gasUsed.toString(), sweep: [], field: [], lens: {} };

  // ---------------------------------------------------------------- sweep
  const polys = fs.existsSync(path.join(DATA, "polygons.json"))
    ? JSON.parse(fs.readFileSync(path.join(DATA, "polygons.json"), "utf8"))
    : {};
  const baSao = polys.BaSao ? ringToPoints(polys.BaSao.vertices) : null;

  const centre = { lat: 10.5937, lon: 105.7016 };
  for (const n of [4, 6, 12, 17, 24, 32]) {
    const poly = regularPolygon(n, centre.lat, centre.lon, 400);
    const pid = id(`sweep-${n}`);
    const rTx = await reg.registerPlot(pid, poly, 50, 100);
    const rRc = await rTx.wait();

    // a point clearly inside (centre) and one clearly outside (1 km east)
    const insideTx = await reg.verifyEvidence(pid, id(`m-in-${n}`), toE7(centre.lat), toE7(centre.lon));
    const insideRc = await insideTx.wait();

    const outLon = centre.lon + 1000 / (111194.9266 * Math.cos((centre.lat * Math.PI) / 180));
    const outTx = await reg.verifyEvidence(pid, id(`m-out-${n}`), toE7(centre.lat), toE7(outLon));
    const outRc = await outTx.wait();

    const view = await reg.locate(pid, toE7(centre.lat), toE7(outLon));

    results.sweep.push({
      vertices: n,
      registerGas: Number(rRc.gasUsed),
      verifyInsideGas: Number(insideRc.gasUsed),
      verifyOutsideGas: Number(outRc.gasUsed),
      outsideDistanceMetres: Number(view[1]),
    });
    // the probe sits 1000 m from the centre of a 400 m-radius ring, so the
    // expected boundary distance is 600 m
    console.log(
      `n=${String(n).padStart(2)}  register=${String(rRc.gasUsed).padStart(8)}  ` +
        `verify(in)=${String(insideRc.gasUsed).padStart(7)}  verify(out)=${String(outRc.gasUsed).padStart(7)}  ` +
        `d_out=${view[1]}m (expected 600m)`
    );
  }

  // ------------------------------------------------------- real field data
  console.log("\n--- validation against production events ---");
  const events = readEvents();
  const lots = { BaSao: polys.BaSao, DakLak: polys.DakLak, NutriGreen: polys.NutriGreen };

  for (const [lot, meta] of Object.entries(lots)) {
    if (!meta) continue;
    const poly = ringToPoints(meta.vertices);
    const pid = id(`lot-${lot}`);
    await (await reg.registerPlot(pid, poly, 50, 100)).wait();

    for (const ev of events.filter((e) => e.lot === lot)) {
      const lat = toE7(parseFloat(ev.lat));
      const lon = toE7(parseFloat(ev.lon));
      const [inside, dist, tier] = await reg.locate(pid, lat, lon);
      const sys = parseInt(ev.dist_m_system, 10);
      const onchain = Number(dist);
      results.field.push({
        lot,
        event: Number(ev.event_no),
        systemMetres: sys,
        onchainMetres: onchain,
        inside,
        tier: Number(tier),
        deltaMetres: onchain - sys,
      });
    }
  }

  // agreement summary, reported per lot and for the stable-boundary subset
  function summarise(rows) {
    const deltas = rows.map((r) => Math.abs(r.deltaMetres));
    const containment = rows.filter((r) => (r.systemMetres === 0) === r.inside).length;
    return {
      events: rows.length,
      containmentAgreement: containment,
      meanAbsDeltaMetres: rows.length
        ? Number((deltas.reduce((a, b) => a + b, 0) / rows.length).toFixed(3))
        : 0,
      maxAbsDeltaMetres: rows.length ? Math.max(...deltas) : 0,
      outsideEvents: rows.filter((r) => r.systemMetres > 0).length,
    };
  }

  results.agreement = { perLot: {}, stableBoundarySubset: null };
  for (const lot of ["BaSao", "NutriGreen", "DakLak"]) {
    const rows = results.field.filter((r) => r.lot === lot);
    if (!rows.length) continue;
    const s = summarise(rows);
    results.agreement.perLot[lot] = s;
    console.log(
      `${lot.padEnd(11)} n=${String(s.events).padStart(2)}  containment=${s.containmentAgreement}/${s.events}  ` +
        `mean|Δd|=${s.meanAbsDeltaMetres}m  max|Δd|=${s.maxAbsDeltaMetres}m`
    );
  }

  // Đắk Lắk is excluded from the headline figure: its plot was reassigned mid-cycle
  // (a supported operation for products that move between parcels), so two of its
  // events were originally graded against a different boundary than the one on file.
  const stable = results.field.filter((r) => r.lot !== "DakLak");
  results.agreement.stableBoundarySubset = summarise(stable);
  const s = results.agreement.stableBoundarySubset;
  console.log(
    `\nstable-boundary subset (Ba Sao + NutriGreen): n=${s.events}  ` +
      `containment=${s.containmentAgreement}/${s.events}  mean|Δd|=${s.meanAbsDeltaMetres}m  max|Δd|=${s.maxAbsDeltaMetres}m`
  );

  // ---------------------------------------------------------------- lens
  const Lens = await hre.ethers.getContractFactory("LensRegistry");
  const lens = await Lens.deploy();
  await lens.waitForDeployment();
  const lensDeploy = await hre.ethers.provider.getTransactionReceipt(
    lens.deploymentTransaction().hash
  );
  const pubRc = await (
    await lens.publish(id("eudr-v1"), hre.ethers.keccak256(hre.ethers.toUtf8Bytes('{"green":30,"yellow":80}')))
  ).wait();
  results.lens = { deployGas: Number(lensDeploy.gasUsed), publishGas: Number(pubRc.gasUsed) };
  console.log(`\nLensRegistry deploy=${lensDeploy.gasUsed}  publish=${pubRc.gasUsed}`);

  const out = path.join(DATA, "benchmark_results.json");
  fs.writeFileSync(out, JSON.stringify(results, null, 2));
  console.log(`\nwrote ${out}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
