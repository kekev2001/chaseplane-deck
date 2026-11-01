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
// the user's own ChasePlane key bindings as the Bridge would return them (text format of user_settings.json -> control_mappings)
const MAPPINGS = [
  'CAM_QUICK_VIEW_UP&1|Keyboard|162|2|0;1|Keyboard|164|2|0;1|Keyboard|118|2|0;',          // Ctrl+Alt+F7
  'CAM_BOOST_SET&1|Keyboard|33|2|0;',                                                    // PageUp (a default)
  'CAM_ROLL_L&1|Keyboard|160|2|0;1|Keyboard|75|2|0;',                                    // Shift+K: this user chose their own key
  'CAM_TOGGLE_NVG&0|Mouse|3|2|0;',                                                       // mouse only: no key to press
  'CAM_ZOOM_IN&1|Keyboard|160|2|0;1|Keyboard|79|2|0;',
  'CAM_ZOOM_IN&1|Keyboard|160|2|0;1|Keyboard|107|2|0;',                                  // a second binding: the first one is used
  '',
].join('\n');
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
          if (m.command === 'get_all_assignments') payload = { message: 'get_assignments', payload: { aircraft: 'Boeing 737-800', devices: [], events: [], views: [], groups: [], mappings: MAPPINGS, keyboard_naming: [], named_assignments: [] } };
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
const CTX = { cockpit: 'ctx-cockpit', external: 'ctx-external', toggle: 'ctx-toggle', cine: 'ctx-cine', tower: 'ctx-tower', drone: 'ctx-drone', v1: 'ctx-v1', v2: 'ctx-v2', v9: 'ctx-v9', vw: 'ctx-vw', status: 'ctx-status', flash: 'ctx-flash',
  peekU: 'ctx-peekU', boost: 'ctx-boost', roll: 'ctx-roll', nvg: 'ctx-nvg', zoom: 'ctx-zoom', speedF: 'ctx-speedF', speedS: 'ctx-speedS', fake: 'ctx-fake', nocmd: 'ctx-nocmd', rollR: 'ctx-rollR', head: 'ctx-head' };
const ACTION = { cockpit: 'mode.cockpit', external: 'mode.external', toggle: 'mode.toggle', cine: 'cinematic.toggle', tower: 'near.tower', drone: 'world.drone', v1: 'view', v2: 'view', v9: 'view', vw: 'view', status: 'status', flash: 'flashlight.toggle',
  peekU: 'cmd', boost: 'cmd', roll: 'cmd', nvg: 'cmd', zoom: 'cmd', speedF: 'cmd', speedS: 'cmd', fake: 'cmd', nocmd: 'cmd', rollR: 'cmd', head: 'cmd' };
const SETTINGS = { v1: { slot: 1, mode: 'auto' }, v2: { slot: 2, mode: 'auto' }, v9: { slot: 9, mode: 0 }, vw: { slot: 2, mode: 2 },
  peekU: { command: 'CAM_QUICK_VIEW_UP' }, boost: { command: 'CAM_BOOST_SET' }, roll: { command: 'CAM_ROLL_L' }, nvg: { command: 'CAM_TOGGLE_NVG' }, zoom: { command: 'CAM_ZOOM_IN' },
  speedF: { command: 'CAM_CONTROL_PROFILE_FAST' }, speedS: { command: 'CAM_CONTROL_PROFILE_SLOW' }, fake: { command: 'CAM_NOT_A_REAL_COMMAND' }, nocmd: {}, rollR: { command: 'CAM_ROLL_R' }, head: { command: 'CAM_HEAD_TRACKING_TOGGLE' } };
const sdSrv = new WSServer({ port: 0, host: '127.0.0.1' });
sdSrv.on('connection', (ws) => {
  sdSock = ws;
  ws.on('message', (data) => { const m = JSON.parse(String(data)); if (m.uuid && !registered) registered = m; else sdMsgs.push(m); });
});
const sdSend = (o) => sdSock.send(JSON.stringify(o));
const press = (k) => sdSend({ event: 'keyDown', action: P + ACTION[k], context: CTX[k], payload: { settings: SETTINGS[k] || {} } });
const release = (k) => sdSend({ event: 'keyUp', action: P + ACTION[k], context: CTX[k], payload: { settings: SETTINGS[k] || {} } });
const KS_LOG = path.join(tmp, 'keysend.log');
const ksLines = () => (fs.existsSync(KS_LOG) ? fs.readFileSync(KS_LOG, 'utf8').split('\n').filter(Boolean) : []);
const last = (ctx, ev) => { for (let i = sdMsgs.length - 1; i >= 0; i--) if (sdMsgs[i].context === ctx && sdMsgs[i].event === ev) return sdMsgs[i]; return null; };
const count = (ctx, ev) => sdMsgs.filter((m) => m.context === ctx && m.event === ev).length;

(async () => {
  await startBridge();
  const node = process.execPath;
  const child = spawn(node, [PLUGIN, '-port', String(sdSrv.address().port), '-pluginUUID', 'PLUGIN-UUID', '-registerEvent', 'registerPlugin', '-info', '{"application":{"version":"7.4"}}'],
    { env: Object.assign({}, process.env, { CHASEPLANE_BRIDGE_URL: 'ws://127.0.0.1:' + bridgePort, CHASEPLANE_KEY_IMG_DIR: imgDir, CHASEPLANE_DECK_LOG: path.join(tmp, 'plugin.log'),
      CPDECK_KEYSEND: path.join(__dirname, 'keysend-stub.js'), CPDECK_KEYSEND_LOG: KS_LOG, CPDECK_KEYSEND_REFUSE: path.join(tmp, 'refuse'), CHASEPLANE_SETTINGS_FILE: path.join(tmp, 'no-such-user_settings.json') }), stdio: ['ignore', 'pipe', 'pipe'] });
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

  // "command" keys: the plugin presses the key the user has bound in ChasePlane (read from the Bridge), the stub only records it
  check('bindings were requested from the Bridge (get_all_assignments)', await until(() => reqs('get_all_assignments').length >= 1), bridgeLog);
  press('peekU');   check('command key presses the bound keys: Ctrl+Alt+F7 down', await until(() => ksLines().includes('down 162 164 118')), ksLines());
  release('peekU'); check('and releases them when the Stream Deck key is released', await until(() => ksLines().includes('up 162 164 118')), ksLines());
  press('boost');   await sleep(250);
  check('hold key: stays down while the Stream Deck key is held', ksLines().includes('down 33') && !ksLines().includes('up 33'), ksLines());
  release('boost'); check('hold key: released with the Stream Deck key', await until(() => ksLines().includes('up 33')), ksLines());
  press('roll');    check('a shortcut the user changed (Shift+K) is the one that is pressed', await until(() => ksLines().includes('down 160 75')), ksLines()); release('roll');
  press('zoom');    check('with two bindings the first is used', await until(() => ksLines().includes('down 160 79')), ksLines()); release('zoom');
  await until(() => ksLines().includes('up 160 79') && ksLines().includes('up 160 75'));      // the "up" lines can still be on their way
  const n0 = ksLines().length, aN = count(CTX.nvg, 'showAlert');
  press('nvg');     check('mouse-only binding: no key to press -> showAlert, nothing sent', await until(() => count(CTX.nvg, 'showAlert') === aN + 1) && ksLines().length === n0, ksLines()); release('nvg');
  const aF = count(CTX.fake, 'showAlert'); press('fake');
  check('command without any binding -> showAlert, nothing sent', await until(() => count(CTX.fake, 'showAlert') === aF + 1) && ksLines().length === n0, ksLines()); release('fake');
  const aC = count(CTX.nocmd, 'showAlert'); press('nocmd');
  check('command key without a command -> showAlert', await until(() => count(CTX.nocmd, 'showAlert') === aC + 1)); release('nocmd');
  // another window is in front (the helper refuses "down"/"tap" then): the key flashes and nothing is held
  fs.writeFileSync(path.join(tmp, 'refuse'), '1');
  const aP = count(CTX.peekU, 'showAlert'), nP = ksLines().length; press('peekU');
  check('flight simulator not in front -> showAlert (keys are never typed into another window)', await until(() => count(CTX.peekU, 'showAlert') === aP + 1) && ksLines().length === nP + 1, ksLines());
  release('peekU'); await sleep(250);
  check('... and nothing is "released" afterwards (it never went down)', ksLines().length === nP + 1, ksLines());
  fs.unlinkSync(path.join(tmp, 'refuse'));
  check('the plugin starts the helper with --require-foreground FlightSimulator', ksLines().some((l) => /^args: --parent \d+ --require-foreground FlightSimulator$/.test(l)), ksLines().slice(0, 2));
  const n1 = ksLines().length;                                    // after the refused press above
  press('speedF');  check('speed key goes through the Bridge: set_control_profile {mode:2}', await until(() => reqs('set_control_profile').some((e) => e.payload.mode === 2)), reqs('set_control_profile')); release('speedF');
  press('speedS');  check('speed slow -> set_control_profile {mode:0}, and no key sent', await until(() => reqs('set_control_profile').some((e) => e.payload.mode === 0)) && ksLines().length === n1, ksLines()); release('speedS');
  const downs = () => ksLines().filter((l) => l === 'down 162 164 118').length, ups = () => ksLines().filter((l) => l === 'up 162 164 118').length;
  const d0 = downs(), u0 = ups();
  press('peekU');   await until(() => downs() === d0 + 1);
  sdSend({ event: 'willDisappear', action: P + 'cmd', context: CTX.peekU, payload: {} });
  check('page changes while a key is held -> its keys are released (no stuck key)', await until(() => ups() === u0 + 1), ksLines());
  sdSend({ event: 'willAppear', action: P + 'cmd', context: CTX.peekU, device: 'DEV', payload: { controller: 'Keypad', settings: SETTINGS.peekU, state: 0 } });
  check('no error was logged by the key helper', !/keysend (error|stderr)|could not start keysend/.test(fs.existsSync(path.join(tmp, 'plugin.log')) ? fs.readFileSync(path.join(tmp, 'plugin.log'), 'utf8') : ''));

  // the speed keys and head tracking light up from what the Bridge reports in cam_mode_set (control_profile, head_tracking_enabled)
  bridgeClients[0].send(JSON.stringify({ message: 'cam_mode_set', payload: { mode: 0, preset_guid: 'c1', views_loaded: true, control_profile: 2, head_tracking_enabled: true } }));
  check('speed profile Fast active: Fast key lit, Slow key not', await until(() => (last(CTX.speedF, 'setState') || {}).payload && last(CTX.speedF, 'setState').payload.state === 1 && last(CTX.speedS, 'setState').payload.state === 0), [last(CTX.speedF, 'setState'), last(CTX.speedS, 'setState')]);
  check('head tracking on: its key is lit', await until(() => (last(CTX.head, 'setState') || {}).payload && last(CTX.head, 'setState').payload.state === 1), last(CTX.head, 'setState'));
  bridgeClients[0].send(JSON.stringify({ message: 'cam_mode_set', payload: { mode: 0, preset_guid: 'c1', views_loaded: true, control_profile: 1, head_tracking_enabled: false } }));
  check('profile back to Normal and head tracking off: keys go dark', await until(() => last(CTX.speedF, 'setState').payload.state === 0 && last(CTX.head, 'setState').payload.state === 0));
  bridgeClients[0].send(JSON.stringify({ message: 'camera_runtime_state', payload: { master_enabled: true } }));
  bridgeClients[0].send(JSON.stringify({ message: 'sim_state', payload: { latitude: 51.9, flashlight_enabled: true } }));
  check('flashlight state is also taken from sim_state', await until(() => (last(CTX.flash, 'setState') || {}).payload.state === 1), last(CTX.flash, 'setState'));
  bridgeClients[0].send(JSON.stringify({ message: 'sim_state', payload: { latitude: 51.9, flashlight_enabled: false } }));
  check('... and goes dark again', await until(() => last(CTX.flash, 'setState').payload.state === 0));

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
  const b0 = ksLines().filter((l) => l === 'down 33').length;
  press('boost');   check('command key still works while the Bridge is offline (bindings are remembered)', await until(() => ksLines().filter((l) => l === 'down 33').length === b0 + 1), ksLines()); release('boost');
  const aS = count(CTX.speedF, 'showAlert'); press('speedF');
  check('speed key while the Bridge is offline -> showAlert (needs the Bridge)', await until(() => count(CTX.speedF, 'showAlert') === aS + 1)); release('speedF');

  // bridge comes back on the same port
  nestedReplies = true; const before = bridgeLog.length;
  await startBridge(port);
  check('plugin reconnects by itself (within ~3 s)', await until(() => bridgeLog.slice(before).some((e) => e.connect), 8000));
  check('after reconnect: views reloaded with NESTED reply shape handled', await until(() => (last(CTX.status, 'setState') || {}).payload.state === 1 && (last(CTX.v1, 'setTitle') || {}).payload.title === 'Captain', 6000), [last(CTX.status, 'setState'), last(CTX.v1, 'setTitle')]);

  child.kill();
  const logTxt = fs.existsSync(path.join(tmp, 'plugin.log')) ? fs.readFileSync(path.join(tmp, 'plugin.log'), 'utf8') : '';
  console.log('\n--- plugin log (tail) ---\n' + logTxt.split('\n').slice(-14).join('\n'));

  // ---- second plugin instance with NO Bridge at all: the bindings come from ChasePlane's settings file (control_mappings is one JSON string)
  const settingsFile = path.join(tmp, 'user_settings.json'), KS_LOG2 = path.join(tmp, 'keysend2.log');
  fs.writeFileSync(settingsFile, '﻿' + JSON.stringify({ version: 1, control_mappings: 'CAM_ROLL_R&1|Keyboard|162|2|0;1|Keyboard|76|2|0;\nCAM_MOVE_F&1|Keyboard|160|2|0;1|Keyboard|87|2|0;\nCAM_FOO&1|Keyboard|35|2|0;\n' }));
  registered = null; sdMsgs.length = 0;
  const child2 = spawn(node, [PLUGIN, '-port', String(sdSrv.address().port), '-pluginUUID', 'PLUGIN-UUID', '-registerEvent', 'registerPlugin', '-info', '{}'],
    { env: Object.assign({}, process.env, { CHASEPLANE_BRIDGE_URL: 'ws://127.0.0.1:1', CHASEPLANE_KEY_IMG_DIR: imgDir, CHASEPLANE_DECK_LOG: path.join(tmp, 'plugin2.log'),
      CPDECK_KEYSEND: path.join(__dirname, 'keysend-stub.js'), CPDECK_KEYSEND_LOG: KS_LOG2, CHASEPLANE_SETTINGS_FILE: settingsFile }), stdio: ['ignore', 'pipe', 'pipe'] });
  check('second plugin instance registers (no Bridge running)', await until(() => registered), registered);
  sdSend({ event: 'willAppear', action: P + 'cmd', context: CTX.rollR, device: 'DEV', payload: { controller: 'Keypad', settings: SETTINGS.rollR, state: 0 } });
  await sleep(300); press('rollR');
  check('without the Bridge the key is taken from the settings file (BOM, one JSON string)', await until(() => fs.existsSync(KS_LOG2) && fs.readFileSync(KS_LOG2, 'utf8').includes('down 162 76')), fs.existsSync(KS_LOG2) ? fs.readFileSync(KS_LOG2, 'utf8') : '(no log)');
  release('rollR');
  check('and released again', await until(() => fs.readFileSync(KS_LOG2, 'utf8').includes('up 162 76')));
  check('the plugin starts its key helper with --parent <its own pid> (so the helper ends with it)', fs.readFileSync(KS_LOG2, 'utf8').includes('args: --parent ' + child2.pid), fs.readFileSync(KS_LOG2, 'utf8'));
  child2.kill();

  // ---- parsing of the key bindings (unit tests of the plugin's own functions)
  const unit = require(PLUGIN);
  const asArr = (m) => JSON.stringify([...m]);
  check('parseMappingText: stored order, both separators, mouse-only and mixed lines skipped',
    asArr(unit.parseMappingText('A_B&1|Keyboard|162|2|0;1|Keyboard|75|2|0;\nA_B\\u00261|Keyboard|35|2|0;\nM&0|Mouse|1|2|0;\nX&1|Keyboard|160|2|0;0|Mouse|1|2|0;\n')) === JSON.stringify([['A_B', [[162, 75], [35]]]]));
  check('extractBindings: mappings as text inside the nested reply (4 commands have a key, the mouse-only one does not count)', unit.extractBindings({ message: 'get_assignments', payload: { mappings: MAPPINGS } }).size === 4);
  check('extractBindings: mappings as an array of lines', unit.extractBindings({ mappings: MAPPINGS.split('\n') }).size === 4);
  check('extractBindings: objects with Keyboard entries',
    asArr(unit.extractBindings({ mappings: [{ event: 'CAM_BINOCULARS', bindings: [{ device: 'Keyboard', code: 162 }, { device: 'Keyboard', code: 79 }] }] })) === JSON.stringify([['CAM_BINOCULARS', [[162, 79]]]]));
  check('extractBindings: unrecognised reply gives an empty result, no crash', unit.extractBindings({ foo: 1, bar: ['x'] }).size === 0 && unit.extractBindings(null).size === 0 && unit.extractBindings('text').size === 0);

  // ---- the real key helper, in --dry mode only: it must parse the protocol and send nothing
  const ksExe = path.join(path.dirname(PLUGIN), 'keysend.exe');
  if (fs.existsSync(ksExe)) {
    const out = await new Promise((resolve) => {
      const p = spawn(ksExe, ['--dry']); let s = '';
      p.stdout.on('data', (d) => { s += d; }); p.on('close', () => resolve(s));
      p.stdin.end('down 162 164 118\nup 162 164 118\ntap 160 72\nbogus\ndown 999\ndown\ndown 160 75\n');
    });
    check('keysend.exe --dry: down / up / tap / errors; keys still down are released when the input closes',
      JSON.stringify(out.split(/\r?\n/).filter(Boolean)) === JSON.stringify(['ok dry +162 +164 +118', 'ok dry -118 -164 -162', 'ok dry +160 +72 -72 -160', "err unknown command 'bogus'", "err bad key code '999'", 'err no key codes', 'ok dry +160 +75', 'bye dry -75 -160']), out);
    // --require-foreground: with a program name that is certainly not in front, "down" and "tap" are refused, "up" still works
    const out2 = await new Promise((resolve) => {
      const p = spawn(ksExe, ['--dry', '--require-foreground', 'zz-no-such-program-zz']); let s = '';
      p.stdout.on('data', (d) => { s += d; }); p.on('close', () => resolve(s));
      p.stdin.end('down 160 72\ntap 160 72\nup 160 72\nforeground\n');
    });
    const l2 = out2.split(/\r?\n/).filter(Boolean);
    check('keysend.exe --require-foreground: down/tap refused when another window is in front, up still works, "foreground" names the window',
      /^err not-foreground \S+/.test(l2[0]) && /^err not-foreground \S+/.test(l2[1]) && l2[2] === 'ok dry -72 -160' && /^ok \S+/.test(l2[3]) && !/not-foreground/.test(l2[3]), out2);
    // the plugin process is killed hard while the helper holds a key: the helper must notice and end (--parent)
    const holder = spawn(process.execPath, ['-e', `const { spawn } = require('child_process'); const p = spawn(${JSON.stringify(ksExe)}, ['--dry', '--parent', String(process.pid)], { stdio: ['pipe', 'pipe', 'ignore'] }); p.stdin.write('down 160 75\\n'); console.log(p.pid); setInterval(() => {}, 1000);`], { stdio: ['ignore', 'pipe', 'inherit'] });
    const helperPid = await new Promise((resolve) => { holder.stdout.once('data', (d) => resolve(parseInt(String(d), 10))); });
    await sleep(400);
    const alive = (pid) => { try { process.kill(pid, 0); return true; } catch (e) { return false; } };
    const wasAlive = alive(helperPid);
    holder.kill();
    check('keysend.exe ends by itself when its parent process is killed', wasAlive && await until(() => !alive(helperPid), 6000), { helperPid, wasAlive });
  } else console.log('SKIP keysend.exe --dry test (build the plugin first)');
  console.log(`\n${checks - failures}/${checks} checks passed`);
  await stopBridge().catch(() => {}); sdSrv.close();
  fs.rmSync(tmp, { recursive: true, force: true });
  process.exit(failures ? 1 : 0);
})().catch((e) => { console.error('TEST CRASH', e); process.exit(2); });
