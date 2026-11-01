'use strict';
// End-to-end test of the plugin against a fake Stream Deck app and a fake ChasePlane Bridge.
// Both fakes use the independent "ws" library, so the plugin's own WebSocket client is checked against a standard server.
// Needs the "ws" package: run `npm install ws` in the test folder (any Node 18+), or set CP_TEST_WS to the path of an installed copy. Then run:
//   node test/plugin-test.js          (or with the Node that Stream Deck ships: %APPDATA%\Elgato\StreamDeck\NodeJS\20.20.2\node.exe)
const path = require('path');
const fs = require('fs');
const os = require('os');
const { spawn } = require('child_process');

function loadWs() {
  for (const c of [process.env.CP_TEST_WS, 'ws', path.join(__dirname, 'node_modules', 'ws')].filter(Boolean)) {
    try { return require(c); } catch (e) { /* try the next place */ }
  }
  console.error('The "ws" package is needed for this test: run "npm install ws" in the test folder, or set CP_TEST_WS to its path.');
  process.exit(2);
}
const { Server: WSServer } = loadWs();
const PLUGIN = path.join(__dirname, '..', 'plugin', 'com.chaseplanexl.deck.sdPlugin', 'bin', 'plugin.js');
const P = 'com.chaseplanexl.deck.';

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cpdeck-'));
const imgDir = path.join(tmp, 'keys'); fs.mkdirSync(imgDir);
for (const n of ['view_m0', 'view_m0_lit', 'view_m1', 'view_m1_lit', 'view_m2', 'view_m2_lit', 'view_empty', 'view_offline']) fs.writeFileSync(path.join(imgDir, n + '.png'), 'PNG:' + n);
const b64 = (n) => 'data:image/png;base64,' + Buffer.from('PNG:' + n).toString('base64');

let failures = 0, checks = 0;
function check(name, ok, extra) { checks++; if (!ok) failures++; console.log((ok ? 'PASS ' : 'FAIL ') + name + (ok || extra === undefined ? '' : '  -> ' + JSON.stringify(extra))); }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(fn, ms = 4000) { const t = Date.now(); while (Date.now() - t < ms) { if (fn()) return true; await sleep(25); } return false; }

// ---- fake Bridge
const views = [
  { guid: 'c1', name: 'Captain', mode: 0, order: 0, view_type: 'ONBOARD_PIC' },
  { guid: 'c2', name: 'First Officer', mode: 0, order: 1, view_type: 'ONBOARD_PIC' },
  { guid: 'c3', name: 'Overhead Panel', mode: 0, order: 2, view_type: 'ONBOARD_PIC' },
  { guid: 'e1', name: 'Chase', mode: 1, order: 0, view_type: 'OUTSIDE_CHASE' },
  { guid: 'e2', name: 'Wing Left', mode: 1, order: 1, view_type: 'OUTSIDE_CHASE' },
  { guid: 'w1', name: 'Tower', mode: 2, order: 0, view_type: 'WORLD_TOWER' },
  { guid: 'w2', name: 'Runway', mode: 2, order: 1, view_type: 'WORLD_RUNWAY' },
  { guid: 'w3', name: 'Drone', mode: 2, order: 2, view_type: 'WORLD_DRONE' },
  { guid: 'w4', name: 'Flyby', mode: 2, order: 3, view_type: 'WORLD_FLYBY' },
];
// pad past 64 KB so the 16-bit/64-bit frame length paths are exercised
const bigViews = views.concat(Array.from({ length: 700 }, (_, i) => ({ guid: 'x' + i, name: 'Extra view number ' + i + ' ' + 'z'.repeat(60), mode: 2, order: 100 + i, view_type: 'WORLD_DEFAULT' })));
let bridgeSrv = null, bridgePort = 0;
const bridgeLog = [];           // every api_request received
let bridgeClients = [];
let nestedReplies = false, failGuid = null;
function startBridge(port = 0) {
  return new Promise((resolve) => {
    bridgeSrv = new WSServer({ port, host: '127.0.0.1' }, () => { bridgePort = bridgeSrv.address().port; resolve(); });
    bridgeSrv.on('connection', (ws) => {
      bridgeClients.push(ws);
      ws.on('message', (data) => {
        const m = JSON.parse(String(data));
        if (m.message === 'api_connect') {
          bridgeLog.push({ connect: m.payload });
          ws.send(JSON.stringify({ message: 'api_version', payload: { version: '1.0' } }));
          ws.send('PING');
          ws.ping();
          ws.send(JSON.stringify({ message: 'initialized', payload: { sim: 'MSFS2024' } }));
          ws.send(JSON.stringify({ message: 'cam_mode_set', payload: { mode: 0, preset_guid: 'c1', views_loaded: true } }));
          ws.send(JSON.stringify({ message: 'camera_runtime_state', payload: { master_enabled: true, flashlight_enabled: false, cinematic_enabled: false } }));
        } else if (m.message === 'api_request') {
          bridgeLog.push({ command: m.command, payload: m.payload });
          let status = 200, payload = {};
          if (m.command === 'get_views') payload = { views: bigViews, metadata: { aircraft_readable: 'Boeing 737-800' } };
          if (m.command === 'set_view_by_guid' && m.payload.guid === failGuid) status = 404;
          const body = nestedReplies && m.command === 'get_views' ? { message: 'views', payload } : payload;
          ws.send(JSON.stringify({ message: 'api_reply', request_id: m.request_id, status, payload: body, error: status === 200 ? undefined : 'not found' }));
        }
      });
    });
  });
}
const stopBridge = () => new Promise((resolve) => { for (const c of bridgeClients) c.terminate(); bridgeClients = []; bridgeSrv.close(() => resolve()); });
const reqs = (cmd) => bridgeLog.filter((e) => e.command === cmd);

// ---- fake Stream Deck app
const sdMsgs = [];                // everything the plugin sent after registering
let sdSock = null, registered = null;
const CTX = { cockpit: 'ctx-cockpit', external: 'ctx-external', toggle: 'ctx-toggle', cine: 'ctx-cine', tower: 'ctx-tower', drone: 'ctx-drone', v1: 'ctx-v1', v2: 'ctx-v2', v9: 'ctx-v9', vw: 'ctx-vw', status: 'ctx-status', flash: 'ctx-flash' };
const ACTION = { cockpit: 'mode.cockpit', external: 'mode.external', toggle: 'mode.toggle', cine: 'cinematic.toggle', tower: 'near.tower', drone: 'world.drone', v1: 'view', v2: 'view', v9: 'view', vw: 'view', status: 'status', flash: 'flashlight.toggle' };
const SETTINGS = { v1: { slot: 1, mode: 'auto' }, v2: { slot: 2, mode: 'auto' }, v9: { slot: 9, mode: 0 }, vw: { slot: 2, mode: 2 } };
const sdSrv = new WSServer({ port: 0, host: '127.0.0.1' });
sdSrv.on('connection', (ws) => {
  sdSock = ws;
  ws.on('message', (data) => { const m = JSON.parse(String(data)); if (m.uuid && !registered) registered = m; else sdMsgs.push(m); });
});
const sdSend = (o) => sdSock.send(JSON.stringify(o));
const press = (k) => sdSend({ event: 'keyDown', action: P + ACTION[k], context: CTX[k], payload: { settings: SETTINGS[k] || {} } });
const last = (ctx, ev) => { for (let i = sdMsgs.length - 1; i >= 0; i--) if (sdMsgs[i].context === ctx && sdMsgs[i].event === ev) return sdMsgs[i]; return null; };
const count = (ctx, ev) => sdMsgs.filter((m) => m.context === ctx && m.event === ev).length;

(async () => {
  await startBridge();
  const node = process.execPath;
  const child = spawn(node, [PLUGIN, '-port', String(sdSrv.address().port), '-pluginUUID', 'PLUGIN-UUID', '-registerEvent', 'registerPlugin', '-info', '{"application":{"version":"7.4"}}'],
    { env: Object.assign({}, process.env, { CHASEPLANE_BRIDGE_URL: 'ws://127.0.0.1:' + bridgePort, CHASEPLANE_KEY_IMG_DIR: imgDir, CHASEPLANE_DECK_LOG: path.join(tmp, 'plugin.log') }), stdio: ['ignore', 'pipe', 'pipe'] });
  child.stderr.on('data', (d) => console.log('[plugin stderr]', String(d).trim()));

  check('plugin registers with Stream Deck', await until(() => registered), registered);
  check('register message is correct', registered && registered.event === 'registerPlugin' && registered.uuid === 'PLUGIN-UUID', registered);
  check('plugin sends api_connect with client name', await until(() => bridgeLog.some((e) => e.connect && e.connect.client_name === 'ChasePlane Deck')), bridgeLog);

  // keys appear
  for (const k of Object.keys(CTX)) sdSend({ event: 'willAppear', action: P + ACTION[k], context: CTX[k], device: 'DEV', payload: { controller: 'Keypad', settings: SETTINGS[k] || {}, state: 0 } });
  check('get_views requested after ready', await until(() => reqs('get_views').length >= 1), bridgeLog);
  check('large get_views reply (>64KB) handled: view slot 1 titled "Captain"', await until(() => (last(CTX.v1, 'setTitle') || {}).payload && last(CTX.v1, 'setTitle').payload.title === 'Captain'), sdMsgs.filter((m) => m.context === CTX.v1));
  check('view slot 1 is lit (active view c1) and uses cockpit image', (last(CTX.v1, 'setImage') || {}).payload && last(CTX.v1, 'setImage').payload.image === b64('view_m0_lit'), last(CTX.v1, 'setImage'));
  check('view slot 2 shows "First Officer" not lit', (last(CTX.v2, 'setTitle') || {}).payload && last(CTX.v2, 'setTitle').payload.title === 'First\nOfficer' && last(CTX.v2, 'setImage').payload.image === b64('view_m0'), [last(CTX.v2, 'setTitle'), last(CTX.v2, 'setImage')]);
  check('empty slot 9 shows the empty tile', (last(CTX.v9, 'setImage') || {}).payload && last(CTX.v9, 'setImage').payload.image === b64('view_empty'));
  check('fixed world slot (mode 2, slot 2) shows "Runway"', (last(CTX.vw, 'setTitle') || {}).payload && last(CTX.vw, 'setTitle').payload.title === 'Runway', last(CTX.vw, 'setTitle'));
  check('cockpit key lit (state 1), external key not lit', (last(CTX.cockpit, 'setState') || {}).payload.state === 1 && (last(CTX.external, 'setState') || {}).payload.state === 0);
  check('status key online with mode + aircraft', (last(CTX.status, 'setState') || {}).payload.state === 1 && /COCKPIT\nBoeing/.test((last(CTX.status, 'setTitle') || {}).payload.title), last(CTX.status, 'setTitle'));

  // key presses
  press('external'); check('press External -> set_camera_mode {mode:1}', await until(() => reqs('set_camera_mode').some((e) => e.payload.mode === 1)), reqs('set_camera_mode'));
  bridgeClients[0].send(JSON.stringify({ message: 'cam_mode_set', payload: { mode: 0, preset_guid: 'c1', views_loaded: true } })); await sleep(150);
  press('toggle');  check('press In/Out while camera=cockpit -> set_camera_mode {mode:1}', await until(() => reqs('set_camera_mode').filter((e) => e.payload.mode === 1).length >= 2), reqs('set_camera_mode'));
  bridgeClients[0].send(JSON.stringify({ message: 'cam_mode_set', payload: { mode: 0, preset_guid: 'c1', views_loaded: true } })); await sleep(150);
  press('v2');      check('press view slot 2 -> set_view_by_guid c2', await until(() => reqs('set_view_by_guid').some((e) => e.payload.guid === 'c2')), reqs('set_view_by_guid'));
  check('slot 2 lights up right after (optimistic)', await until(() => (last(CTX.v2, 'setImage') || {}).payload && last(CTX.v2, 'setImage').payload.image === b64('view_m0_lit')), last(CTX.v2, 'setImage'));
  press('tower');   check('press Tower -> cam_go_to_nearest {kind:"tower"}', await until(() => reqs('cam_go_to_nearest').some((e) => e.payload.kind === 'tower')), reqs('cam_go_to_nearest'));
  press('drone');   check('press Drone -> set_view_by_guid w3', await until(() => reqs('set_view_by_guid').some((e) => e.payload.guid === 'w3')), reqs('set_view_by_guid'));
  press('cine');    check('press Cinematic -> cam_cinematic_toggle', await until(() => reqs('cam_cinematic_toggle').length === 1));
  press('flash');   check('press Flashlight -> cam_flashlight_toggle', await until(() => reqs('cam_flashlight_toggle').length === 1));
  const alertsBefore = count(CTX.v9, 'showAlert');
  press('v9');      check('press empty slot -> showAlert, no request', await until(() => count(CTX.v9, 'showAlert') === alertsBefore + 1) && reqs('set_view_by_guid').every((e) => e.payload.guid !== undefined && !String(e.payload.guid).startsWith('x')));
  failGuid = 'w3'; const a2 = count(CTX.drone, 'showAlert'); press('drone');
  check('server error reply (404) -> showAlert', await until(() => count(CTX.drone, 'showAlert') === a2 + 1));
  failGuid = null;

  // events from the bridge
  bridgeClients[0].send(JSON.stringify({ message: 'cam_mode_set', payload: { mode: 1, preset_guid: 'e2', views_loaded: true } }));
  check('mode change to External: slot 1 now "Chase", slot 2 lit "Wing Left"', await until(() => (last(CTX.v1, 'setTitle') || {}).payload.title === 'Chase' && (last(CTX.v2, 'setTitle') || {}).payload.title === 'Wing Left' && last(CTX.v2, 'setImage').payload.image === b64('view_m1_lit')), [last(CTX.v1, 'setTitle'), last(CTX.v2, 'setImage')]);
  check('External key lit, Cockpit key unlit', (last(CTX.external, 'setState') || {}).payload.state === 1 && (last(CTX.cockpit, 'setState') || {}).payload.state === 0);
  press('toggle');  check('press In/Out while camera=external -> set_camera_mode {mode:0}', await until(() => reqs('set_camera_mode').some((e) => e.payload.mode === 0)), reqs('set_camera_mode'));
  bridgeClients[0].send(JSON.stringify({ message: 'camera_runtime_state', payload: { flashlight_enabled: true, cinematic_enabled: true } }));
  check('flashlight + cinematic keys light from runtime state', await until(() => (last(CTX.flash, 'setState') || {}).payload.state === 1 && (last(CTX.cine, 'setState') || {}).payload.state === 1));
  const gv = reqs('get_views').length;
  bridgeClients[0].send(JSON.stringify({ message: 'view_modified', payload: {} }));
  check('view_modified triggers a views refresh', await until(() => reqs('get_views').length === gv + 1));

  // property inspector request
  sdSend({ event: 'sendToPlugin', action: P + 'view', context: 'pi-ctx', payload: { request: 'views', mode: 'auto' } });
  check('PI request answered with view names', await until(() => sdMsgs.some((m) => m.event === 'sendToPropertyInspector' && m.payload.online && m.payload.names.length > 0)), sdMsgs.filter((m) => m.event === 'sendToPropertyInspector'));

  // bridge goes away
  const port = bridgePort;
  await stopBridge();
  check('bridge drops: status key goes offline', await until(() => (last(CTX.status, 'setState') || {}).payload.state === 0 && /OFFLINE/.test(last(CTX.status, 'setTitle').payload.title)), last(CTX.status, 'setTitle'));
  check('bridge drops: view slots show offline tile', (last(CTX.v1, 'setImage') || {}).payload.image === b64('view_offline'));
  const a3 = count(CTX.cockpit, 'showAlert'); press('cockpit');
  check('press while offline -> showAlert', await until(() => count(CTX.cockpit, 'showAlert') === a3 + 1));

  // bridge comes back on the same port
  nestedReplies = true; const before = bridgeLog.length;
  await startBridge(port);
  check('plugin reconnects by itself (within ~3 s)', await until(() => bridgeLog.slice(before).some((e) => e.connect), 8000));
  check('after reconnect: views reloaded with NESTED reply shape handled', await until(() => (last(CTX.status, 'setState') || {}).payload.state === 1 && (last(CTX.v1, 'setTitle') || {}).payload.title === 'Captain', 6000), [last(CTX.status, 'setState'), last(CTX.v1, 'setTitle')]);

  child.kill();
  const logTxt = fs.existsSync(path.join(tmp, 'plugin.log')) ? fs.readFileSync(path.join(tmp, 'plugin.log'), 'utf8') : '';
  console.log('\n--- plugin log (tail) ---\n' + logTxt.split('\n').slice(-14).join('\n'));
  console.log(`\n${checks - failures}/${checks} checks passed`);
  await stopBridge().catch(() => {}); sdSrv.close();
  fs.rmSync(tmp, { recursive: true, force: true });
  process.exit(failures ? 1 : 0);
})().catch((e) => { console.error('TEST CRASH', e); process.exit(2); });
