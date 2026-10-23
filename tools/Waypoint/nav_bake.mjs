// The navigation bake of one map tile: its triangle soup (nav_extract.py) rasterized by Recast into
// a compact heightfield, the walkable floors of every column of the ground with their links to
// the neighbouring columns' floors. Several floors a column: a road under a bridge, a cave under a hill.
//
//   node tools/Waypoint/nav_bake.mjs <in.bin> <out.chf> [north0 north1 west0 west1]
//
// Only solid triangles (kind 0) are rasterized; liquid surfaces are left to the reduce step.
// The character (AGENT): HEIGHT yards tall needs that much room over a floor, CLIMB yards is the
// highest step it walks up, SLOPE degrees the steepest ground it walks on, RADIUS yards from a wall
// its middle stays (the floors are eroded by it).
//
// Out (little-endian): "WCHF", version, width, height (cells along x = north and z = -west),
// bmin x, y, z, cs, ch (float32), span count; cells as uint32 (index:24 | count:8, Recast's
// rcCompactCell), spans as 2 uint32 (y:16 | reg:16, con:24 | h:8, Recast's rcCompactSpan), areas as uint8.
import { readFileSync, writeFileSync } from 'node:fs';
import {
  init, Raw, RecastBuildContext, allocHeightfield, createHeightfield, markWalkableTriangles,
  rasterizeTriangles, filterLowHangingWalkableObstacles, filterLedgeSpans, filterWalkableLowHeightSpans,
  allocCompactHeightfield, buildCompactHeightfield, erodeWalkableArea, freeHeightfield, freeCompactHeightfield,
  FloatArray, IntArray, UnsignedCharArray,
} from '@recast-navigation/core';

export const CS = 0.5;      // yards across a cell
export const CH = 0.2;      // yards a height step
export const AGENT = { HEIGHT: 2.0, CLIMB: 1.0, SLOPE: 50, RADIUS: 0.5 };
const TILE = 1600 / 3;
const MAX = 32 * TILE;
const MARGIN = 4;           // yards past the tile baked too, so its edge cells have neighbours

function readSoup(path) {
  const b = readFileSync(path);
  if (b.toString('latin1', 0, 4) !== 'WNAV') throw new Error('not a soup: ' + path);
  const nv = b.readUInt32LE(8), nt = b.readUInt32LE(12);
  let o = 16;
  const verts = new Float32Array(b.buffer.slice(b.byteOffset + o, b.byteOffset + o + nv * 12)); o += nv * 12;
  const tris = new Int32Array(b.buffer.slice(b.byteOffset + o, b.byteOffset + o + nt * 12)); o += nt * 12;
  const kinds = new Uint8Array(b.buffer.slice(b.byteOffset + o, b.byteOffset + o + nt));
  return { verts, tris, kinds, nv, nt };
}

export async function bake(inPath, outPath, bounds) {
  await init();
  const soup = readSoup(inPath);
  // Solid triangles only.
  const solid = [];
  for (let i = 0; i < soup.nt; i++) if (soup.kinds[i] === 0) solid.push(soup.tris[3 * i], soup.tris[3 * i + 1], soup.tris[3 * i + 2]);
  const nt = solid.length / 3;
  let ymin = Infinity, ymax = -Infinity;
  for (let i = 1; i < soup.verts.length; i += 3) { ymin = Math.min(ymin, soup.verts[i]); ymax = Math.max(ymax, soup.verts[i]); }
  // x = north, z = -west.
  const [n0, n1, w0, w1] = bounds;
  const bmin = [n0 - MARGIN, ymin - 1, -w1 - MARGIN];
  const bmax = [n1 + MARGIN, ymax + AGENT.HEIGHT + 1, -w0 + MARGIN];
  const width = Math.ceil((bmax[0] - bmin[0]) / CS), height = Math.ceil((bmax[2] - bmin[2]) / CS);

  const ctx = new RecastBuildContext();
  const hf = allocHeightfield();
  if (!createHeightfield(ctx, hf, width, height, bmin, bmax, CS, CH)) throw new Error('heightfield');
  const verts = new FloatArray(); verts.copy(soup.verts);
  const tris = new IntArray(); tris.copy(solid);
  const areas = new UnsignedCharArray(); areas.copy(new Array(nt).fill(0));
  markWalkableTriangles(ctx, AGENT.SLOPE, verts, soup.nv, tris, nt, areas);
  const climb = Math.floor(AGENT.CLIMB / CH), tall = Math.ceil(AGENT.HEIGHT / CH);
  if (!rasterizeTriangles(ctx, verts, soup.nv, tris, areas, nt, hf, climb)) throw new Error('rasterize');
  filterLowHangingWalkableObstacles(ctx, climb, hf);
  filterLedgeSpans(ctx, tall, climb, hf);
  filterWalkableLowHeightSpans(ctx, tall, hf);
  const chf = allocCompactHeightfield();
  if (!buildCompactHeightfield(ctx, tall, climb, hf, chf)) throw new Error('compact');
  freeHeightfield(hf);
  erodeWalkableArea(ctx, Math.ceil(AGENT.RADIUS / CS), chf);

  // Straight out of the module's memory: the cells, spans and areas arrays.
  const M = Raw.Module;
  const ncells = chf.width() * chf.height(), nspans = chf.spanCount();
  const cellPtr = M.getPointer(chf.raw.get_cells(0));
  const spanPtr = M.getPointer(chf.raw.get_spans(0));
  const cells = new Uint32Array(M.HEAPU8.buffer.slice(cellPtr, cellPtr + ncells * 4));
  const spans = new Uint32Array(M.HEAPU8.buffer.slice(spanPtr, spanPtr + nspans * 8));
  const areaOut = new Uint8Array(nspans);
  for (let i = 0; i < nspans; i++) areaOut[i] = chf.areas(i);
  const head = Buffer.alloc(4 + 4 * 4 + 5 * 4 + 4);
  let o = 0;
  head.write('WCHF', o); o += 4;
  head.writeUInt32LE(1, o); o += 4;
  head.writeUInt32LE(chf.width(), o); o += 4;
  head.writeUInt32LE(chf.height(), o); o += 4;
  const b = chf.bmin();
  for (const v of [b.x, b.y, b.z, chf.cs(), chf.ch()]) { head.writeFloatLE(v, o); o += 4; }
  head.writeUInt32LE(nspans, o); o += 4;
  writeFileSync(outPath, Buffer.concat([head.subarray(0, o), Buffer.from(cells.buffer), Buffer.from(spans.buffer), Buffer.from(areaOut.buffer)]));
  freeCompactHeightfield(chf);
  return { width: chf.width(), height: chf.height(), spans: nspans, tris: nt };
}

function tileBounds(name) {
  const [, ty, tx] = name.split('_').map(Number);
  return [MAX - (ty + 1) * TILE, MAX - ty * TILE, MAX - (tx + 1) * TILE, MAX - tx * TILE];
}

// node nav_bake.mjs <in.bin> <out.chf> [north0 north1 west0 west1]
// node nav_bake.mjs --list <file of "in.bin out.chf" lines>
if (process.argv[1] && process.argv[1].endsWith('nav_bake.mjs')) {
  const args = process.argv.slice(2);
  const jobs = args[0] === '--list'
    ? readFileSync(args[1], 'utf8').split(/\r?\n/).filter(Boolean).map((l) => l.split('\t'))
    : [[args[0], args[1], ...args.slice(2)]];
  for (const [inPath, outPath, ...b] of jobs) {
    const name = inPath.split(/[\\/]/).pop().replace('.bin', '');
    const t = Date.now();
    try {
      const r = await bake(inPath, outPath, b.length === 4 ? b.map(Number) : tileBounds(name));
      console.log(`${name}: ${r.width}x${r.height} cells, ${r.spans} floors from ${r.tris} triangles in ${((Date.now() - t) / 1000).toFixed(1)}s`);
    } catch (e) {
      console.log(`${name}: FAILED ${e.message}`);
    }
  }
}
