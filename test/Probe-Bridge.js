'use strict';
// Read-only look at a RUNNING ChasePlane Bridge: asks for the key bindings (get_all_assignments) and the views (get_views), saves the raw replies
// and shows what the plugin's own parser makes of them. It changes nothing in ChasePlane and presses no keys.
//   node test\Probe-Bridge.js [output-folder]        (needs Node 22 or newer; MSFS + ChasePlane must be running)
const fs = require('fs');
const path = require('path');
const outDir = process.argv[2] || path.join(__dirname, 'probe-output');
fs.mkdirSync(outDir, { recursive: true });
const plugin = require(path.join(__dirname, '..', 'plugin', 'com.chaseplanexl.deck.sdPlugin', 'bin', 'plugin.js'));

const URL = process.env.CHASEPLANE_BRIDGE_URL || 'ws://127.0.0.1:8652';
const ws = new WebSocket(URL);
const pending = new Map();
let seq = 0, ready = false, lastCam = null;
const done = (code, msg) => { if (msg) console.log(msg); try { ws.close(); } catch (e) { /* ignore */ } setTimeout(() => process.exit(code), 200); };
setTimeout(() => done(1, 'Timed out after 15 s: is MSFS + ChasePlane running?'), 15000);

function request(command, payload = {}) {
  return new Promise((resolve, reject) => {
    const id = `${command}_${Date.now()}_${++seq}`;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ message: 'api_request', request_id: id, command, payload }));
  });
}
function shape(v, depth = 0) {                       // a compact description of a JSON value (types and sizes, no personal data)
  if (v === null) return 'null';
  if (Array.isArray(v)) return `array(${v.length})` + (v.length && depth < 3 ? ' of ' + shape(v[0], depth + 1) : '');
  if (typeof v === 'object') return depth > 3 ? 'object' : '{' + Object.keys(v).slice(0, 14).map((k) => k + ': ' + shape(v[k], depth + 1)).join(', ') + '}';
  if (typeof v === 'string') return 'string(' + v.length + ')';
  return typeof v;
}
async function run() {
  console.log('Connected to', URL, '- asking for the key bindings and the views (read-only)');
  const assignments = await request('get_all_assignments');
  const views = await request('get_views');
  fs.writeFileSync(path.join(outDir, 'get_all_assignments.reply.json'), JSON.stringify(assignments, null, 1));
  fs.writeFileSync(path.join(outDir, 'get_views.reply.json'), JSON.stringify(views, null, 1).slice(0, 200000));
  console.log('\nget_all_assignments reply (raw, before the plugin unwraps it):', shape(assignments));
  // the plugin unwraps nested { message, payload } replies; do the same here
  let inner = assignments.payload;
  for (let i = 0; i < 4 && inner && typeof inner === 'object' && 'payload' in inner && ('message' in inner || 'status' in inner); i++) inner = inner.payload;
  console.log('after unwrapping:', shape(inner));
  const map = plugin.extractBindings(inner);
  console.log(`\nThe plugin's parser found keyboard bindings for ${map.size} commands.`);
  for (const [cmd, combos] of [...map.entries()].slice(0, 80)) console.log('  ' + cmd.padEnd(30) + combos.map((c) => c.join('+')).join('  |  '));
  const want = ['CAM_QUICK_VIEW_UP', 'CAM_QUICK_VIEW_DOWN', 'CAM_QUICK_VIEW_BEHIND', 'CAM_BINOCULARS', 'CAM_ROLL_L', 'CAM_TOGGLE_NVG', 'CAM_EXPOSURE_MORE', 'CAM_HEAD_TRACKING_TOGGLE', 'CAM_TOGGLE_DOF'];
  console.log('\nCommands the deck needs a key for, and what the user has:');
  for (const c of want) console.log('  ' + c.padEnd(30) + (map.has(c) ? map.get(c).map((x) => x.join('+')).join('  |  ') : '(no key assigned)'));
  console.log('\nRaw replies saved in', outDir);
  if (process.argv.includes('--test-speed')) await testSpeed();
  done(0);
}
// OPTIONAL (--test-speed): the only thing here that changes anything. Sets the camera speed profile to another value, waits for the Bridge to
// report it, and puts the original value back straight away. Skipped when the speed profile is "custom".
async function testSpeed() {
  const orig = lastCam && lastCam.control_profile;
  if (![0, 1, 2].includes(orig)) { console.log('\n--test-speed skipped: the current control_profile is', orig); return; }
  const other = orig === 2 ? 1 : 2;
  console.log(`\n--test-speed: control_profile is ${orig}; setting ${other}, then back to ${orig}`);
  const seenAfter = (value) => new Promise((resolve) => { const t = Date.now(); const iv = setInterval(() => { if (lastCam && lastCam.control_profile === value) { clearInterval(iv); resolve(true); } else if (Date.now() - t > 3000) { clearInterval(iv); resolve(false); } }, 50); });
  try {
    const r1 = await request('set_control_profile', { mode: other });
    console.log('  set_control_profile', other, '-> status', r1.status, ' Bridge reports it:', await seenAfter(other));
  } finally {
    const r2 = await request('set_control_profile', { mode: orig });
    console.log('  set_control_profile', orig, '(restore) -> status', r2.status, ' Bridge reports it:', await seenAfter(orig));
  }
}
ws.addEventListener('open', () => ws.send(JSON.stringify({ message: 'api_connect', payload: { client_name: 'ChasePlane Deck Probe' } })));
ws.addEventListener('error', () => done(1, 'Could not connect to ' + URL));
ws.addEventListener('message', (ev) => {
  const text = String(ev.data);
  if (text === 'PING' || text === 'PING_BRIDGE') return;
  let m; try { m = JSON.parse(text); } catch (e) { return; }
  if (m.message === 'cam_mode_set' && m.payload) lastCam = m.payload;
  if (m.message === 'api_reply') {
    const p = pending.get(m.request_id);
    if (p) { pending.delete(m.request_id); if (m.status === 200) p.resolve(m); else p.reject(new Error(`${m.error || 'error'} (${m.status})`)); }
  } else if ((m.message === 'initialized' || m.message === 'ready') && !ready) {
    ready = true; run().catch((e) => done(1, 'Failed: ' + e.message));
  }
});
