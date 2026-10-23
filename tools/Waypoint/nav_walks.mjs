// Walking times between fixed places (flight masters, docks, towns) over a whole map's ground,
// for nav_pack.py: from each place, the quickest way to every other (Dijkstra over every node,
// stopping once all places are settled).
//
//   node tools/Waypoint/nav_walks.mjs <in.bin> <out.bin>
//
// In (little-endian): "WWIN", node count, edge count, place count; edges as CSR: start per node
// (n + 1, int32), target (int32), walk, swim, fixed seconds (float32 each); the places' nodes (int32).
// Out: "WWOT", place count; for each place, to each place: walk, swim, fixed seconds (float32;
// -1 when there's no way).
import { readFileSync, writeFileSync } from 'node:fs';

const [inPath, outPath] = process.argv.slice(2);
const b = readFileSync(inPath);
const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
if (b.toString('latin1', 0, 4) !== 'WWIN') throw new Error('bad input');
const n = dv.getInt32(4, true), m = dv.getInt32(8, true), np = dv.getInt32(12, true);
let o = 16;
const view = (T, count) => { const a = new T(b.buffer.slice(b.byteOffset + o, b.byteOffset + o + count * T.BYTES_PER_ELEMENT)); o += count * T.BYTES_PER_ELEMENT; return a; };
const start = view(Int32Array, n + 1);
const target = view(Int32Array, m);
const walk = view(Float32Array, m);
const swim = view(Float32Array, m);
const fixed = view(Float32Array, m);
const places = view(Int32Array, np);

const placeIdx = new Int32Array(n).fill(-1);
places.forEach((p, i) => { if (placeIdx[p] < 0) placeIdx[p] = i; });

const dist = new Float64Array(n).fill(Infinity);
const ws = new Float64Array(n), ss = new Float64Array(n), fs = new Float64Array(n);
const done = new Uint8Array(n);
let hk = new Float64Array(1 << 16), hv = new Int32Array(1 << 16), size = 0;
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

const out = new Float32Array(np * np * 3).fill(-1);
const touched = [];
for (let s = 0; s < np; s++) {
  for (const v of touched) { dist[v] = Infinity; done[v] = 0; }
  touched.length = 0;
  const src = places[s];
  dist[src] = 0; ws[src] = 0; ss[src] = 0; fs[src] = 0; touched.push(src);
  size = 0; push(0, src);
  let left = np;
  while (size > 0 && left > 0) {
    const u = pop();
    if (done[u]) continue;
    done[u] = 1;
    if (placeIdx[u] >= 0) {
      // every place on this node (two places can share one)
      for (let j = 0; j < np; j++) {
        if (places[j] === u) {
          out[(s * np + j) * 3] = ws[u]; out[(s * np + j) * 3 + 1] = ss[u]; out[(s * np + j) * 3 + 2] = fs[u];
          left--;
        }
      }
    }
    const du = dist[u];
    for (let e = start[u]; e < start[u + 1]; e++) {
      const v = target[e];
      if (done[v]) continue;
      const nd = du + walk[e] + swim[e] + fixed[e];
      if (nd < dist[v]) {
        if (dist[v] === Infinity) touched.push(v);
        dist[v] = nd; ws[v] = ws[u] + walk[e]; ss[v] = ss[u] + swim[e]; fs[v] = fs[u] + fixed[e];
        push(nd, v);
      }
    }
  }
}
const buf = Buffer.alloc(8 + out.byteLength);
buf.write('WWOT', 0); buf.writeInt32LE(np, 4);
Buffer.from(out.buffer).copy(buf, 8);
writeFileSync(outPath, buf);
console.log(`${np} places walked`);
