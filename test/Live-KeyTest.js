'use strict';
// LIVE test of the key path, against a running MSFS + ChasePlane. Run it only while the MSFS window is in front (click on it first).
// It reads the key the user has bound to CAM_TOGGLE_IN_OUT from the Bridge, presses exactly that key with keysend.exe (which refuses unless a
// FlightSimulator window is in front) and watches the Bridge's cam_mode_set: the camera must switch between cockpit and external, and it presses
// the key a second time to switch back. Nothing else is touched.
//   node test\Live-KeyTest.js
const path = require('path');
const { spawn } = require('child_process');
const plugin = require(path.join(__dirname, '..', 'plugin', 'com.chaseplanexl.deck.sdPlugin', 'bin', 'plugin.js'));
const KEYSEND = path.join(__dirname, '..', 'plugin', 'com.chaseplanexl.deck.sdPlugin', 'bin', 'keysend.exe');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const ws = new WebSocket(process.env.CHASEPLANE_BRIDGE_URL || 'ws://127.0.0.1:8652');
let cam = null, assignments = null, ready = false;
const fail = (msg) => { console.log('RESULT: FAIL - ' + msg); process.exit(1); };
setTimeout(() => fail('timed out after 90 s'), 90000);
ws.addEventListener('error', () => fail('cannot connect to the Bridge (is MSFS + ChasePlane running?)'));
ws.addEventListener('open', () => ws.send(JSON.stringify({ message: 'api_connect', payload: { client_name: 'ChasePlane Deck Live Test' } })));
ws.addEventListener('message', (ev) => {
  const t = String(ev.data); if (t === 'PING' || t === 'PING_BRIDGE') return;
  let m; try { m = JSON.parse(t); } catch (e) { return; }
  if (m.message === 'cam_mode_set' && m.payload) cam = m.payload;
  if (m.message === 'api_reply' && m.request_id === 'ga') {
    let h = m.payload; for (let i = 0; i < 4 && h && typeof h === 'object' && 'payload' in h && ('message' in h || 'status' in h); i++) h = h.payload;
    assignments = h;
  }
  if ((m.message === 'initialized' || m.message === 'ready') && !ready) { ready = true; ws.send(JSON.stringify({ message: 'api_request', request_id: 'ga', command: 'get_all_assignments', payload: {} })); setTimeout(run, 1500); }
});

async function run() {
  if (!assignments || !cam) return fail('no assignments or camera state received');
  const combo = (plugin.extractBindings(assignments).get('CAM_TOGGLE_IN_OUT') || [])[0];
  if (!combo) return fail('the user has no keyboard key bound to CAM_TOGGLE_IN_OUT');
  console.log('CAM_TOGGLE_IN_OUT is bound to virtual key(s) ' + combo.join('+') + '; camera mode now ' + cam.mode);
  const ks = spawn(KEYSEND, ['--parent', String(process.pid), '--require-foreground', 'FlightSimulator'], { stdio: ['pipe', 'pipe', 'inherit'] });
  const answers = []; let buf = '';
  ks.stdout.on('data', (d) => { buf += d; let i; while ((i = buf.indexOf('\n')) >= 0) { answers.push(buf.slice(0, i).trim()); buf = buf.slice(i + 1); } });
  const ask = async (line) => { const n = answers.length; ks.stdin.write(line + '\n'); const t = Date.now(); while (answers.length === n && Date.now() - t < 3000) await sleep(20); return answers[n] || 'err no answer'; };
  // wait (up to 60 s) until the flight simulator window has been in front for a second; nothing is pressed before that
  let front = await ask('foreground'), steady = 0, told = false;
  for (let i = 0; i < 120 && steady < 2; i++) {
    front = await ask('foreground');
    if (/FlightSimulator/i.test(front)) steady++;
    else { steady = 0; if (!told) { console.log('Waiting for the MSFS window to come to the front (now in front: ' + front + '). Click on MSFS now...'); told = true; } await sleep(500); }
    if (steady === 1) await sleep(500);
  }
  console.log('window in front: ' + front);
  const waitMode = async (want) => { const t = Date.now(); while (Date.now() - t < 3000) { if (cam && cam.mode === want) return true; await sleep(50); } return false; };
  const m0 = cam.mode, other = m0 === 0 ? 1 : 0;
  const r1 = await ask('tap ' + combo.join(' '));
  if (/not-foreground/.test(r1)) return fail('the flight simulator window is not in front (' + r1 + '). Click on the MSFS window and run this again.');
  if (!/^ok/.test(r1)) return fail('key helper said: ' + r1);
  const changed = await waitMode(other);
  console.log('pressed the user\'s own key: camera mode ' + (changed ? 'changed ' + m0 + ' -> ' + cam.mode + '  (the key reached ChasePlane)' : 'did NOT change within 3 s'));
  if (changed) {
    await ask('tap ' + combo.join(' '));
    const back = await waitMode(m0);
    console.log('pressed again: camera mode ' + (back ? 'is back to ' + cam.mode : 'did not come back (mode is ' + cam.mode + ')'));
    console.log(back ? 'RESULT: PASS' : 'RESULT: PARTIAL - the first press worked, the second did not switch back; please check the camera');
    process.exit(back ? 0 : 1);
  }
  console.log('RESULT: FAIL - the key was sent but ChasePlane did not react (a held press may be needed, or injected keys are ignored)');
  process.exit(1);
}
