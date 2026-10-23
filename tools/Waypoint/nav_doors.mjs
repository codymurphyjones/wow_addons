// The crossing times inside each tile between its doors (nav_pack.py): from every door's node, the
// quickest way to every other door node of the same tile, without leaving it.
//
//   node tools/Waypoint/nav_doors.mjs <in.bin> <out.bin>
//
// In (little-endian, from nav_pack.py): "WDIN", node count, edge count, door node count; per node
// its tile (int32); edges as CSR: start per node (n + 1, int32), target (int32), walk seconds and
// swim seconds (float32 each); door nodes (int32), grouped by tile.
// Out: "WDOT", edge count; per edge from, to (int32), walk seconds, swim seconds (float32): the two
// parts of the quickest way (by their sum).
import { readFileSync, writeFileSync } from 'node:fs';

const [inPath, outPath] = process.argv.slice(2);
const b = readFileSync(inPath);
const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
if (b.toString('latin1', 0, 4) !== 'WDIN') throw new Error('bad input');
const n = dv.getInt32(4, true), m = dv.getInt32(8, true), nd = dv.getInt32(12, true);
let o = 16;
const view = (T, count) => { const a = new T(b.buffer.slice(b.byteOffset + o, b.byteOffset + o + count * T.BYTES_PER_ELEMENT)); o += count * T.BYTES_PER_ELEMENT; return a; };
const tile = view(Int32Array, n);
const start = view(Int32Array, n + 1);
const target = view(Int32Array, m);
const walk = view(Float32Array, m);
const swim = view(Float32Array, m);
const doors = view(Int32Array, nd);

// Door nodes per tile, and which are doors.
const isDoor = new Uint8Array(n);
const byTile = new Map();
for (const d of doors) {
  isDoor[d] = 1;
  if (!byTile.has(tile[d])) byTile.set(tile[d], []);
  byTile.get(tile[d]).push(d);
}

const dist = new Float64Array(n).fill(Infinity);
const wsec = new Float64Array(n), ssec = new Float64Array(n);
const touched = [];
// Binary heap of (key, node).
let hk = new Float64Array(1024), hv = new Int32Array(1024), size = 0;
function push(k, v) {
  if (size + 1 >= hk.length) {
    const nk = new Float64Array(hk.length * 2); nk.set(hk); hk = nk;
    const nv = new Int32Array(hv.length * 2); nv.set(hv); hv = nv;
  }
  let i = ++size;
  while (i > 1) { const p = i >> 1; if (hk[p] <= k) break; hk[i] = hk[p]; hv[i] = hv[p]; i = p; }
  hk[i] = k; hv[i] = v;
}
function pop() {
  const v = hv[1], lk = hk[size], lv = hv[size]; size--;
  let i = 1;
  while (true) {
    let c = i * 2; if (c > size) break;
    if (c + 1 <= size && hk[c + 1] < hk[c]) c++;
    if (hk[c] >= lk) break;
    hk[i] = hk[c]; hv[i] = hv[c]; i = c;
  }
  hk[i] = lk; hv[i] = lv;
  return v;
}

const out = [];
let runs = 0;
for (const [t, list] of byTile) {
  for (const src of list) {
    for (const v of touched) dist[v] = Infinity;
    touched.length = 0;
    dist[src] = 0; wsec[src] = 0; ssec[src] = 0; touched.push(src);
    size = 0; push(0, src);
    let left = list.length - 1;
    while (size > 0 && left > 0) {
      const u = pop();
      const du = dist[u];
      if (du < 0) continue;            // settled already
      if (isDoor[u] && u !== src) {
        out.push(src, u, wsec[u], ssec[u]);
        left--;
      }
      dist[u] = -1 - du;               // settled: negative
      for (let e = start[u]; e < start[u + 1]; e++) {
        const v = target[e];
        if (tile[v] !== t) continue;
        const dvv = dist[v];
        if (dvv < 0) continue;
        const nd2 = du + walk[e] + swim[e];
        if (nd2 < dvv) {
          if (dvv === Infinity) touched.push(v);
          dist[v] = nd2; wsec[v] = wsec[u] + walk[e]; ssec[v] = ssec[u] + swim[e];
          push(nd2, v);
        }
      }
    }
    runs++;
  }
}
const ne = out.length / 4;
const buf = Buffer.alloc(8 + ne * 16);
buf.write('WDOT', 0); buf.writeInt32LE(ne, 4);
for (let i = 0; i < ne; i++) {
  buf.writeInt32LE(out[4 * i], 8 + i * 16);
  buf.writeInt32LE(out[4 * i + 1], 12 + i * 16);
  buf.writeFloatLE(out[4 * i + 2], 16 + i * 16);
  buf.writeFloatLE(out[4 * i + 3], 20 + i * 16);
}
writeFileSync(outPath, buf);
console.log(`${runs} searches, ${ne} crossings`);
