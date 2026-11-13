#!/usr/bin/env node
// Runs the script of each hand-made HTML animation against a stub DOM and writes
// what it builds and when (element counts, reveal times, timeline values) to
// test/onboarding_art/fixtures/js_truth.json. The Dart tests compare the ports with it.
// Usage: node tool/onboarding_anim/js_truth.js   (needs node; only to regenerate the fixture)
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..', '..');
const src = path.join(root, 'incoming', 'onboarding-animations');

class El {
  constructor(tag) { this.tag = tag; this.attrs = {}; this.children = []; this.dataset = {}; }
  setAttribute(k, v) { this.attrs[k] = String(v); }
  getAttribute(k) { return k in this.attrs ? this.attrs[k] : (k === 'stroke-dasharray' ? '100 105' : '0'); }
  removeAttribute() {}
  appendChild(c) { this.children.push(c); return c; }
  getBBox() { return { x: 0, y: 0, width: 10, height: 10 }; }
  querySelector() { return new El('x'); }
  querySelectorAll() { return []; }
  addEventListener() {}
  getTotalLength() { return 1000; }
  getPointAtLength() { return { x: 0, y: 0 }; }
}

function run(file, probe) {
  const html = fs.readFileSync(path.join(src, file), 'utf8');
  let script = html.match(/<script>([\s\S]*)<\/script>/)[1];
  const created = {};
  const doc = {
    getElementById: id => new El('id:' + id),
    createElementNS: (ns, tag) => { created[tag] = (created[tag] || 0) + 1; return new El(tag); },
    querySelectorAll: () => [], querySelector: () => new El('x'), body: { dataset: {} },
  };
  const ctx = { document: doc, location: { search: '' }, URLSearchParams, Math, console,
    performance: { now: () => 0 }, requestAnimationFrame: () => 0, cancelAnimationFrame() {},
    matchMedia: () => ({ matches: false }) };
  ctx.window = ctx;
  vm.createContext(ctx);
  script = script.replace(/const params = new URLSearchParams[\s\S]*$/, `window.__probe = (${probe});\n})();`);
  vm.runInContext(script, ctx);
  return { created, ...ctx.__probe };
}

const r3 = v => Math.round(v * 1000) / 1000;
const out = {};
out.network = run('network-icons.html', `(() => {
  const people = nodes.filter(n => n.g);
  return {
    period: PERIOD, nodes: nodes.length, people: people.length,
    byLevel: [0, 1, 2, 3].map(l => nodes.filter(n => n.lvl === l).length),
    electrons: E.length, lateral: lat.length,
    reveal: people.map(n => [n.lvl, n.k, +n.t0.toFixed(3), +n.ts.toFixed(3), +n.x.toFixed(1), +n.y.toFixed(1)]),
    spawn: SPAWN, throwAt: THROW, nodeT: nodeT,
  };
})()`);
out.shield = run('shield-security.html', `(() => ({
  arrival: T_ARR, loopStart: S.loopStart, cycle: S.cycle,
}))()`);
out.buildings = run('buildings-switching.html', `(() => ({
  loopStart: LOOP0, period: PERIOD, nodeT, arcStart, arcDur, bub0: BUB0,
  hits: hits.map(h => [+h.t.toFixed(3), h.icon]),
}))()`);
const dest = path.join(root, 'test', 'onboarding_art', 'fixtures', 'js_truth.json');
fs.mkdirSync(path.dirname(dest), { recursive: true });
fs.writeFileSync(dest, JSON.stringify(out, null, 1) + '\n');
console.log('wrote ' + dest);
for (const k of Object.keys(out)) console.log(k, JSON.stringify(out[k].created));
