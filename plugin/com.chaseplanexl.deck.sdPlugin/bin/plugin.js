'use strict';
// ChasePlane Deck - Stream Deck plugin that talks to ChasePlane's local Bridge API (ws://127.0.0.1:8652).
// No dependencies: a small RFC 6455 WebSocket client is included below and used for both the Stream Deck
// connection and the Bridge connection. The Bridge API is undocumented; message names were read from the
// Bridge's own web UI ("ChasePlane Remote"), see README.
const net = require('net');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { EventEmitter } = require('events');

const BRIDGE_URL = process.env.CHASEPLANE_BRIDGE_URL || 'ws://127.0.0.1:8652';
// keysend.exe presses keys for the "command" keys (the Bridge has no command for peek up, roll, night vision ...); see plugin/keysend/KeySend.cs
const KEYSEND = process.env.CPDECK_KEYSEND || path.join(__dirname, 'keysend.exe');
// these three the Bridge can do itself (set_control_profile): no key needed
const SPEED = { CAM_CONTROL_PROFILE_SLOW: 0, CAM_CONTROL_PROFILE_NORMAL: 1, CAM_CONTROL_PROFILE_FAST: 2 };
// "command" keys that light up (their profile entry has a second, lit image); the Bridge reports control_profile and head_tracking_enabled in cam_mode_set
const CMD_LIT = {
  CAM_CONTROL_PROFILE_SLOW: () => cam().control_profile === 0,
  CAM_CONTROL_PROFILE_NORMAL: () => cam().control_profile === 1,
  CAM_CONTROL_PROFILE_FAST: () => cam().control_profile === 2,
  CAM_HEAD_TRACKING_TOGGLE: () => cam().head_tracking_enabled === true,
};
const CLIENT_NAME = 'ChasePlane Deck';
const PREFIX = 'com.chaseplanexl.deck.';
const KEY_IMG_DIR = process.env.CHASEPLANE_KEY_IMG_DIR || path.join(__dirname, '..', 'imgs', 'keys');
const LOG_FILE = process.env.CHASEPLANE_DECK_LOG || path.join(__dirname, '..', 'logs', 'plugin.log');
const MODE_NAMES = ['COCKPIT', 'EXTERNAL', 'WORLD'];
const NEAREST = { WORLD_TOWER: 'tower', WORLD_PARKING: 'parking', WORLD_SPOTTING: 'spotting', WORLD_RUNWAY: 'runway' };
const STATIC = {
  'mode.cockpit':      { run: () => setMode(0), lit: () => cam().mode === 0 },
  'mode.external':     { run: () => setMode(1), lit: () => cam().mode === 1 },
  'mode.world':        { run: () => setMode(2), lit: () => cam().mode === 2 },
  'mode.toggle':       { run: () => setMode(cam().mode === 0 ? 1 : 0), lit: () => cam().mode === 1 },
  'cinematic.toggle':  { run: () => req('cam_cinematic_toggle'), lit: () => flag(['cinematic_enabled', 'cinematic', 'cinematics']) },
  'cinematic.next':    { run: () => req('cam_cinematic_next'), lit: () => false },
  'flashlight.toggle': { run: () => req('cam_flashlight_toggle'), lit: () => flag(['flashlight_enabled', 'flashlight']) },
  'near.tower':        { run: () => req('cam_go_to_nearest', { kind: 'tower' }), lit: () => activeType('WORLD_TOWER') },
  'near.runway':       { run: () => req('cam_go_to_nearest', { kind: 'runway' }), lit: () => activeType('WORLD_RUNWAY') },
  'near.parking':      { run: () => req('cam_go_to_nearest', { kind: 'parking' }), lit: () => activeType('WORLD_PARKING') },
  'near.spotting':     { run: () => req('cam_go_to_nearest', { kind: 'spotting' }), lit: () => activeType('WORLD_SPOTTING') },
  'world.drone':       { run: () => viewByType('WORLD_DRONE', 'drone'), lit: () => activeType('WORLD_DRONE') },
  'world.flyby':       { run: () => viewByType('WORLD_FLYBY', 'flyby'), lit: () => activeType('WORLD_FLYBY') },
  'world.traffic':     { run: () => viewByType('WORLD_TRAFFIC', 'traffic'), lit: () => activeType('WORLD_TRAFFIC') },
};

// ------------------------------------------------------------------ logging
function log(...a) {
  const line = new Date().toISOString() + ' ' + a.map((x) => (typeof x === 'string' ? x : safeJson(x))).join(' ');
  try {
    fs.mkdirSync(path.dirname(LOG_FILE), { recursive: true });
    if (fs.existsSync(LOG_FILE) && fs.statSync(LOG_FILE).size > 512 * 1024) fs.renameSync(LOG_FILE, LOG_FILE + '.old');
    fs.appendFileSync(LOG_FILE, line + '\n');
  } catch (e) { /* logging must never break the plugin */ }
}
function safeJson(x) { try { return JSON.stringify(x); } catch (e) { return String(x); } }
process.on('uncaughtException', (e) => log('uncaughtException', e && e.stack ? e.stack : String(e)));
process.on('unhandledRejection', (e) => log('unhandledRejection', e && e.stack ? e.stack : String(e)));

// ------------------------------------------------------------------ minimal WebSocket client (RFC 6455)
class WS extends EventEmitter {
  constructor(url) {
    super();
    const u = new URL(url);
    this.host = u.hostname; this.port = Number(u.port || 80); this.path = (u.pathname || '/') + (u.search || '');
    this.buf = Buffer.alloc(0); this.open = false; this.closed = false; this.frag = null; this.fragOp = 0;
    this.sock = net.connect({ host: this.host, port: this.port });
    this.sock.setNoDelay(true);
    this.sock.on('connect', () => this._handshake());
    this.sock.on('data', (d) => this._onData(d));
    this.sock.on('error', (e) => this.emit('error', e));
    this.sock.on('close', () => this._finish());
  }
  _handshake() {
    this.key = crypto.randomBytes(16).toString('base64');
    this.sock.write(`GET ${this.path} HTTP/1.1\r\nHost: ${this.host}:${this.port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n` +
      `Sec-WebSocket-Key: ${this.key}\r\nSec-WebSocket-Version: 13\r\n\r\n`);
  }
  _onData(d) {
    this.buf = Buffer.concat([this.buf, d]);
    if (!this.open) {
      const end = this.buf.indexOf('\r\n\r\n');
      if (end < 0) return;
      const head = this.buf.slice(0, end).toString('latin1');
      this.buf = this.buf.slice(end + 4);
      const st = /^HTTP\/1\.\d (\d{3})/.exec(head);
      if (!st || st[1] !== '101') { this.emit('error', new Error('WebSocket handshake failed: ' + head.split('\r\n')[0])); this.sock.destroy(); return; }
      this.open = true;
      this.emit('open');
    }
    this._parse();
  }
  _parse() {
    for (;;) {
      if (this.buf.length < 2) return;
      const b0 = this.buf[0], b1 = this.buf[1];
      const fin = !!(b0 & 0x80), op = b0 & 0x0f, masked = !!(b1 & 0x80);
      let len = b1 & 0x7f, off = 2;
      if (len === 126) { if (this.buf.length < 4) return; len = this.buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (this.buf.length < 10) return; len = this.buf.readUInt32BE(2) * 4294967296 + this.buf.readUInt32BE(6); off = 10; }
      let mask = null;
      if (masked) { if (this.buf.length < off + 4) return; mask = this.buf.slice(off, off + 4); off += 4; }
      if (this.buf.length < off + len) return;
      let payload = this.buf.slice(off, off + len);
      this.buf = this.buf.slice(off + len);
      if (mask) { payload = Buffer.from(payload); for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3]; }
      this._frame(fin, op, payload);
    }
  }
  _frame(fin, op, p) {
    if (op === 0x8) { this._sendFrame(0x8, p.slice(0, 2)); this.sock.end(); return; }
    if (op === 0x9) { this._sendFrame(0xa, p); return; }
    if (op === 0xa) return;
    if (op === 0x0) {
      if (!this.frag) return;
      this.frag.push(p);
      if (fin) { const full = Buffer.concat(this.frag); this.frag = null; this.emit('message', full.toString('utf8')); }
      return;
    }
    if (!fin) { this.frag = [p]; this.fragOp = op; return; }
    this.emit('message', p.toString('utf8'));
  }
  send(text) { return this._sendFrame(0x1, Buffer.from(text, 'utf8')); }
  _sendFrame(op, payload) {
    if (!this.open || this.closed) return false;
    const len = payload.length;
    let head;
    if (len < 126) head = Buffer.alloc(2);
    else if (len < 65536) { head = Buffer.alloc(4); head.writeUInt16BE(len, 2); }
    else { head = Buffer.alloc(10); head.writeUInt32BE(Math.floor(len / 4294967296), 2); head.writeUInt32BE(len >>> 0, 6); }
    head[0] = 0x80 | op;
    head[1] = (len < 126 ? len : len < 65536 ? 126 : 127) | 0x80;
    const mask = crypto.randomBytes(4);
    const body = Buffer.from(payload);
    for (let i = 0; i < body.length; i++) body[i] ^= mask[i & 3];
    this.sock.write(Buffer.concat([head, mask, body]));
    return true;
  }
  close() { try { this._sendFrame(0x8, Buffer.alloc(0)); } catch (e) { /* ignore */ } setTimeout(() => this.sock.destroy(), 200); }
  _finish() { if (this.closed) return; this.closed = true; this.open = false; this.emit('close'); }
}

// ------------------------------------------------------------------ Bridge connection and state
const bridge = { ws: null, ready: false, pending: new Map(), seq: 0, readyTimer: null, version: null };
const model = { camera: null, runtime: null, sim: null, views: [], aircraft: '' };
let viewsTimer = null;

function cam() { return model.camera || { mode: null }; }
function flag(names) {
  for (const src of [model.camera, model.runtime, model.sim]) {
    if (!src) continue;
    for (const n of names) if (typeof src[n] === 'boolean') return src[n];
  }
  return false;
}
function viewOfType(t) { return model.views.find((v) => v && v.view_type === t) || null; }
function activeType(t) { const v = viewOfType(t); return !!(v && model.camera && model.camera.preset_guid === v.guid); }
function viewsForMode(mode) {
  const list = model.views.filter((v) => v && Number(v.mode) === mode);
  const ordered = list.every((v) => typeof v.order === 'number');
  return ordered ? list.slice().sort((a, b) => a.order - b.order) : list;
}

function unwrap(m) {
  let h = m.payload;
  for (let i = 0; i < 4 && h && typeof h === 'object' && 'payload' in h && ('message' in h || 'status' in h); i++) h = h.payload;
  return h;
}
function req(command, payload = {}) {
  return new Promise((resolve, reject) => {
    if (!bridge.ready || !bridge.ws) { reject(new Error('Bridge not connected')); return; }
    const id = `${command}_${Date.now()}_${++bridge.seq}`;
    const timer = setTimeout(() => { bridge.pending.delete(id); reject(new Error('Request timeout: ' + command)); }, 10000);
    bridge.pending.set(id, { resolve, reject, timer, command });
    bridge.ws.send(JSON.stringify({ message: 'api_request', request_id: id, command, payload }));
  });
}
function failPending(err) {
  for (const [, p] of bridge.pending) { clearTimeout(p.timer); p.reject(err); }
  bridge.pending.clear();
}

function connectBridge() {
  let ws;
  try { ws = new WS(BRIDGE_URL); } catch (e) { log('bridge connect error', String(e)); return setTimeout(connectBridge, 3000); }
  bridge.ws = ws; bridge.ready = false;
  let done = false;
  const gone = (why) => {
    if (done) return; done = true;
    clearTimeout(bridge.readyTimer);
    const wasReady = bridge.ready;
    bridge.ready = false; bridge.ws = null;
    failPending(new Error('Bridge disconnected'));
    if (wasReady) log('bridge disconnected', why);
    renderAll();
    setTimeout(connectBridge, 3000);
  };
  ws.on('open', () => {
    log('bridge socket open, sending api_connect');
    ws.send(JSON.stringify({ message: 'api_connect', payload: { client_name: CLIENT_NAME } }));
    bridge.readyTimer = setTimeout(() => { if (!bridge.ready && bridge.ws === ws) { log('no "initialized" within 4s, continuing anyway'); onBridgeReady(); } }, 4000);
  });
  ws.on('message', (text) => onBridgeMessage(text));
  ws.on('error', (e) => { if (bridge.logErr !== String(e)) { bridge.logErr = String(e); log('bridge error', String(e)); } gone('error'); });
  ws.on('close', () => gone('close'));
}
function onBridgeReady() {
  if (bridge.ready) return;
  bridge.ready = true; bridge.logErr = null;
  log('bridge ready');
  refreshViews(0);
  refreshBindings(true);
  renderAll();
}
function onBridgeMessage(text) {
  if (text === 'PING' || text === 'PING_BRIDGE') return;
  let m;
  try { m = JSON.parse(text); } catch (e) { return; }
  switch (m.message) {
    case 'api_version': bridge.version = m.payload && m.payload.version; log('bridge api version', bridge.version); break;
    case 'initialized': case 'ready': clearTimeout(bridge.readyTimer); if (bridge.ready) refreshViews(0); else onBridgeReady(); break;
    case 'cam_mode_set': {
      const wasLoaded = model.camera && model.camera.views_loaded === true;
      model.camera = m.payload || null;
      if (!wasLoaded && model.camera && model.camera.views_loaded === true) refreshViews();
      renderAll();
      break;
    }
    case 'camera_runtime_state': model.runtime = m.payload && typeof m.payload === 'object' ? m.payload : null; renderAll(); break;
    case 'sim_state': model.sim = m.payload && typeof m.payload === 'object' ? m.payload : null; renderAll(); break;      // has flashlight_enabled
    case 'view_created': case 'view_modified': case 'view_deleted': refreshViews(); break;
    case 'api_reply': {
      const p = bridge.pending.get(m.request_id);
      if (!p) break;
      bridge.pending.delete(m.request_id); clearTimeout(p.timer);
      if (m.status === 200) p.resolve(unwrap(m)); else p.reject(new Error(`${m.error || 'error'} (${m.status}) for ${p.command}`));
      break;
    }
    default: break;
  }
}
function refreshViews(delay = 250) {
  clearTimeout(viewsTimer);
  viewsTimer = setTimeout(async () => {
    try {
      const r = await req('get_views');
      if (r && Array.isArray(r.views)) {
        model.views = r.views;
        model.aircraft = (r.metadata && (r.metadata.aircraft_readable || r.metadata.aircraft)) || '';
        log('views loaded', model.views.length, 'aircraft', model.aircraft);
        renderAll();
      } else log('get_views returned unexpected data', r);
    } catch (e) { log('get_views failed', String(e)); }
  }, delay);
}
function setMode(mode) {
  return req('set_camera_mode', { mode }).then((r) => {   // the Bridge also pushes cam_mode_set; this just makes the keys react at once
    model.camera = Object.assign({}, model.camera || {}, { mode });
    renderAll();
    return r;
  });
}
function selectView(v) {
  const kind = NEAREST[v.view_type];
  const p = kind ? req('cam_go_to_nearest', { kind }) : req('set_view_by_guid', { guid: v.guid });
  return p.then((r) => {
    if (!kind) model.camera = Object.assign({}, model.camera || {}, { preset_guid: v.guid, mode: Number(v.mode) });
    renderAll();
    return r;
  });
}
function viewByType(type, label) {
  const v = viewOfType(type);
  if (!v) return Promise.reject(new Error('No ' + label + ' view for this aircraft'));
  return selectView(v);
}

// ------------------------------------------------------------------ the user's own ChasePlane key bindings
// ChasePlane stores keyboard bindings as lines "COMMAND&<flag>|Keyboard|<virtual key>|2|0;<flag>|Keyboard|<virtual key>|2|0;" (modifiers first, the
// key last). The "command" keys of the profiles press whatever key the user has bound to the command, so changed shortcuts keep working.
const LINE_RX = /^([A-Z][A-Z0-9_]*)(?:&|\\u0026)(.*)$/;
function vksOfEntries(rest) {
  const vks = [];
  for (const e of String(rest).split(';')) {
    if (!e.trim()) continue;
    const f = e.split('|');
    if (f.length < 3 || f[1] !== 'Keyboard') return null;       // a mouse / controller part: not something a key press can do
    const vk = parseInt(f[2], 10);
    if (!(vk >= 1 && vk <= 254)) return null;
    vks.push(vk);
  }
  return vks.length ? vks : null;
}
function parseMappingText(text) {          // control_mappings text (user_settings.json) -> Map COMMAND -> [ [vk, vk, ...], ... ]
  const map = new Map();
  for (const raw of String(text || '').split(/\r?\n|\\n/)) {
    const m = LINE_RX.exec(raw.trim());
    if (!m) continue;
    const vks = vksOfEntries(m[2]);
    if (!vks) continue;
    if (!map.has(m[1])) map.set(m[1], []);
    map.get(m[1]).push(vks);
  }
  return map;
}
function collectStrings(node, out, depth = 0) {
  if (out.length > 50000 || depth > 8) return out;
  if (typeof node === 'string') out.push(node);
  else if (Array.isArray(node)) for (const x of node) collectStrings(x, out, depth + 1);
  else if (node && typeof node === 'object') for (const k of Object.keys(node)) collectStrings(node[k], out, depth + 1);
  return out;
}
// The shape of the Bridge's get_all_assignments reply is not documented (the Bridge's own web UI reads aircraft, devices, events, views, groups,
// mappings, keyboard_naming, named_assignments from it). Be tolerant: the mappings as text, any text in the reply that has the line format above,
// or objects with a command name and Keyboard entries.
function extractBindings(reply) {
  let h = reply;
  for (let i = 0; i < 4 && h && typeof h === 'object'; i++, h = h.payload) {
    if (typeof h.mappings === 'string') { const m = parseMappingText(h.mappings); if (m.size) return m; }
  }
  const text = parseMappingText(collectStrings(reply, []).join('\n'));
  if (text.size) return text;
  const map = new Map();
  const walk = (n, d) => {
    if (!n || typeof n !== 'object' || d > 8) return;
    if (Array.isArray(n)) { for (const x of n) walk(x, d + 1); return; }
    const cmd = ['event', 'command', 'name', 'cmd', 'id', 'action'].map((k) => n[k]).find((v) => typeof v === 'string' && /^CAM_[A-Z0-9_]+$/.test(v));
    if (cmd) {
      for (const k of Object.keys(n)) {
        const v = n[k];
        if (typeof v === 'string') { const vks = vksOfEntries(v); if (vks) { if (!map.has(cmd)) map.set(cmd, []); map.get(cmd).push(vks); } }
        else if (Array.isArray(v) && v.length && v.every((x) => x && typeof x === 'object' && /keyboard/i.test(String(x.device || x.type || x.kind || '')) && Number.isFinite(Number(x.code !== undefined ? x.code : (x.vk !== undefined ? x.vk : x.key)))))
          { if (!map.has(cmd)) map.set(cmd, []); map.get(cmd).push(v.map((x) => Number(x.code !== undefined ? x.code : (x.vk !== undefined ? x.vk : x.key)))); }
      }
    }
    for (const k of Object.keys(n)) walk(n[k], d + 1);
  };
  walk(reply, 0);
  return map;
}
function settingsCandidates() {
  if (process.env.CHASEPLANE_SETTINGS_FILE) return [process.env.CHASEPLANE_SETTINGS_FILE];
  const app = process.env.APPDATA || '', local = process.env.LOCALAPPDATA || '';
  return [
    path.join(app, 'Microsoft Flight Simulator 2024', 'WASM', 'MSFS2024', 'p42-util-chaseplane', 'work', 'user_settings.json'),
    path.join(local, 'Packages', 'Microsoft.Limitless_8wekyb3d8bbwe', 'LocalState', 'WASM', 'MSFS2024', 'p42-util-chaseplane', 'work', 'user_settings.json'),
    path.join(app, 'Microsoft Flight Simulator', 'Packages', 'p42-util-chaseplane', 'work', 'user_settings.json'),
    path.join(local, 'Packages', 'Microsoft.FlightSimulator_8wekyb3d8bbwe', 'LocalState', 'packages', 'p42-util-chaseplane', 'work', 'user_settings.json'),
  ];
}
function readSettingsBindings() {          // fallback when the Bridge cannot tell: ChasePlane's own settings file (the newest one if there are several)
  let best = null;
  for (const f of settingsCandidates()) {
    try { const st = fs.statSync(f); if (!best || st.mtimeMs > best.mtime) best = { f, mtime: st.mtimeMs }; } catch (e) { /* not there */ }
  }
  if (!best) return null;
  try { return parseMappingText(JSON.parse(fs.readFileSync(best.f, 'utf8').replace(/^﻿/, '')).control_mappings); }
  catch (e) { log('could not read key bindings from', best.f, String(e)); return null; }
}

const binds = { map: new Map(), source: 'none', at: 0, busy: false, sampleSaved: false, events: [] };
function bindingFor(cmd) { const list = binds.map.get(cmd); return list && list.length ? list[0] : null; }

// ------------------------------------------------------------------ the ChasePlane commands (for the settings page of the "command" key)
// Online the Bridge lists every command ChasePlane knows (get_all_assignments -> events: [{ category, events: [{ event_id, title, description,
// directionals: [{ event_id, title, description }] }] }]); offline the list the build generated from the profiles is used.
const VK_NAMES = { 8: 'Backspace', 9: 'Tab', 13: 'Enter', 19: 'Pause', 20: 'CapsLock', 27: 'Esc', 32: 'Space', 33: 'PageUp', 34: 'PageDown', 35: 'End', 36: 'Home',
  37: 'Left', 38: 'Up', 39: 'Right', 40: 'Down', 44: 'PrintScreen', 45: 'Insert', 46: 'Delete', 91: 'Win', 92: 'Win', 106: 'Num*', 107: 'Num+', 109: 'Num-',
  110: 'Num.', 111: 'Num/', 144: 'NumLock', 145: 'ScrollLock', 160: 'Shift', 161: 'Right Shift', 162: 'Ctrl', 163: 'Right Ctrl', 164: 'Alt', 165: 'Right Alt',
  186: ';', 187: '=', 188: ',', 189: '-', 190: '.', 191: '/', 192: '`', 219: '[', 220: '\\', 221: ']', 222: "'" };
function vkName(vk) {
  if (VK_NAMES[vk]) return VK_NAMES[vk];
  if (vk >= 48 && vk <= 57) return String(vk - 48);
  if (vk >= 65 && vk <= 90) return String.fromCharCode(vk);
  if (vk >= 96 && vk <= 105) return 'Num' + (vk - 96);
  if (vk >= 112 && vk <= 135) return 'F' + (vk - 111);
  return 'key ' + vk;
}
function comboName(vks) { return vks.map(vkName).join('+'); }
function flattenEvents(events) {
  const out = [];
  for (const c of Array.isArray(events) ? events : []) {
    const category = c && typeof c.category === 'string' ? c.category : 'Other';
    for (const e of (c && Array.isArray(c.events)) ? c.events : []) {
      if (!e || typeof e.event_id !== 'string') continue;
      const dirs = Array.isArray(e.directionals) ? e.directionals.filter((d) => d && typeof d.event_id === 'string') : [];
      // an axis such as "Move Laterally" is two commands for a key (left / right): list those, not the axis itself
      const list = dirs.length ? dirs : [e];
      for (const d of list) out.push({ id: d.event_id, title: String(d.title || d.event_id), category, description: String(d.description || e.description || '') });
    }
  }
  return out;
}
function findEvents(reply) {
  let h = reply;
  for (let i = 0; i < 4 && h && typeof h === 'object'; i++, h = h.payload) if (Array.isArray(h.events)) return h.events;
  return [];
}
let knownCommands = null;
function builtInCommands() {
  if (knownCommands) return knownCommands;
  try { knownCommands = JSON.parse(fs.readFileSync(path.join(__dirname, 'known-commands.json'), 'utf8')); } catch (e) { knownCommands = []; }
  return knownCommands;
}
function commandInfo(id) {
  return binds.events.find((c) => c.id === id) || builtInCommands().find((c) => c.id === id) || null;
}
function commandList() {
  const online = binds.events.length > 0;
  const src = online ? binds.events : builtInCommands();
  const commands = src.map((c) => {
    const vks = bindingFor(c.id);
    return { id: c.id, title: c.title || c.id, category: c.category || 'Other', description: c.description || '', bridge: Object.prototype.hasOwnProperty.call(SPEED, c.id), key: vks ? comboName(vks) : null };
  });
  return { source: online ? 'bridge' : 'built-in', commands };
}
async function refreshBindings(force) {
  if (binds.busy) { if (force) binds.again = true; return; }          // a forced refresh that arrives meanwhile runs right after
  if (!force && Date.now() - binds.at < 5000) return;
  binds.busy = true;
  try {
    let map = null, source = '';
    if (bridge.ready) {
      try {
        const r = await req('get_all_assignments');
        if (!binds.sampleSaved) {          // keep the first real reply: it shows what the Bridge really sends
          binds.sampleSaved = true;
          try { fs.writeFileSync(path.join(path.dirname(LOG_FILE), 'assignments-sample.json'), safeJson(r).slice(0, 400000)); } catch (e) { /* diagnostics only */ }
          log('get_all_assignments reply', r && typeof r === 'object' ? Object.keys(r) : typeof r);
        }
        const evs = flattenEvents(findEvents(r));
        if (evs.length) binds.events = evs;
        const m = extractBindings(r);
        if (m.size >= 3) { map = m; source = 'bridge'; } else log('get_all_assignments: no key bindings recognised in the reply');
      } catch (e) { log('get_all_assignments failed', String(e)); }
    }
    if (!map) { const f = readSettingsBindings(); if (f && f.size) { map = f; source = 'settings file'; } }
    if (map) {
      if (source !== binds.source || map.size !== binds.map.size) log('key bindings from', source + ':', map.size, 'commands');
      binds.map = map; binds.source = source;
    } else if (binds.source === 'none') log('no key bindings known yet (Bridge offline and no ChasePlane settings file found)');
  } finally {
    binds.busy = false; binds.at = Date.now();
    if (binds.again) { binds.again = false; refreshBindings(true); }
    renderAll();                                          // titles of "command" keys come from the command list
  }
}

// ------------------------------------------------------------------ keysend.exe: presses the keys
const ks = { proc: null, held: new Map(), waiting: [], buf: '' };          // held: context -> key codes that are down for that Stream Deck key
function keysendFail(why) { const w = ks.waiting; ks.waiting = []; ks.buf = ''; for (const f of w) f('err ' + why); }
function keysendProc() {
  if (ks.proc && ks.proc.exitCode === null && !ks.proc.killed) return ks.proc;
  try {
    const opts = { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true };
    // the helper ends (and lets go of every key) when this plugin process ends, and only types into the flight simulator's window
    const args = ['--parent', String(process.pid)];
    if (process.env.CPDECK_ANYWINDOW !== '1') args.push('--require-foreground', 'FlightSimulator');
    const p = /\.js$/i.test(KEYSEND) ? spawn(process.execPath, [KEYSEND].concat(args), opts) : spawn(KEYSEND, args, opts);
    p.on('error', (e) => { log('keysend error', String(e)); if (ks.proc === p) { ks.proc = null; keysendFail('helper error'); } });
    p.on('exit', (c) => { log('keysend exited', c); if (ks.proc === p) { ks.proc = null; keysendFail('helper exited'); } });
    p.stdin.on('error', () => { /* handled by the exit event */ });
    p.stdout.on('data', (d) => {                                // one answer line per command, in order
      ks.buf += d;
      let i;
      while ((i = ks.buf.indexOf('\n')) >= 0) {
        const line = ks.buf.slice(0, i).trim(); ks.buf = ks.buf.slice(i + 1);
        if (!line) continue;
        const w = ks.waiting.shift();
        if (w) w(line); else log('keysend', line);
      }
    });
    p.stderr.on('data', (d) => log('keysend stderr', String(d).trim()));
    ks.proc = p;
  } catch (e) { log('could not start keysend', String(e)); ks.proc = null; }
  return ks.proc;
}
function sendKeys(verb, vks) {                                  // -> Promise of the helper's answer line ("ok ..." or "err ...")
  return new Promise((resolve) => {
    const p = keysendProc();
    if (!p) { resolve('err no key helper'); return; }
    const timer = setTimeout(() => { log('keysend did not answer; restarting it'); try { p.kill(); } catch (e) { /* ignore */ } if (ks.proc === p) ks.proc = null; keysendFail('no answer'); }, 3000);
    ks.waiting.push((line) => { clearTimeout(timer); resolve(line); });
    try { p.stdin.write(verb + ' ' + vks.join(' ') + '\n'); }
    catch (e) { log('keysend write failed', String(e)); clearTimeout(timer); ks.waiting.pop(); resolve('err ' + e.message); }
  });
}
function releaseHeld(ctx) {
  const vks = ks.held.get(ctx);
  if (vks) { ks.held.delete(ctx); sendKeys('up', vks); }
}
function releaseAll() { for (const ctx of Array.from(ks.held.keys())) releaseHeld(ctx); }
process.on('exit', () => { try { if (ks.proc) ks.proc.kill(); } catch (e) { /* ignore */ } });

// a "command" key: the Bridge for the speed profile, otherwise the key the user has bound to the ChasePlane command
async function commandDown(ctx, k) {
  const cmd = String((k.settings || {}).command || '');
  if (!cmd) { log('command key without a command', k.settings); alertKey(ctx); return; }
  if (Object.prototype.hasOwnProperty.call(SPEED, cmd)) { await req('set_control_profile', { mode: SPEED[cmd] }); return; }
  let combo = bindingFor(cmd);
  if (!combo) { await refreshBindings(true); combo = bindingFor(cmd); }      // maybe the user has just assigned it
  if (!combo) { log('no key assigned in ChasePlane for', cmd, '(run ChasePlane Deck Setup to add it, or assign it in ChasePlane)'); alertKey(ctx); return; }
  releaseHeld(ctx);
  // "hold": the keys stay down while the Stream Deck key is held (move, look, boost ...); "tap": a quick press. Also a quick press when the
  // Stream Deck key was let go while we looked the key up (no stuck key)
  const verb = (k.isDown && (k.settings || {}).mode !== 'tap') ? 'down' : 'tap';
  const reply = await sendKeys(verb, combo);
  if (!/^ok/.test(reply)) {
    if (/not-foreground/.test(reply)) log('key not sent: the flight simulator is not the window in front (' + reply.replace(/^err not-foreground\s*/, '') + ')');
    else log('key not sent for', cmd, reply);
    alertKey(ctx);
    return;
  }
  if (verb === 'down') {
    if (k.isDown) ks.held.set(ctx, combo);
    else sendKeys('up', combo);                                   // released while the helper was answering
  }
}

// ------------------------------------------------------------------ Stream Deck connection
const keys = new Map();            // context -> { id, settings, sent }
let sd = null;

function sdSend(o) { if (sd) sd.send(JSON.stringify(o)); }
function setState(ctx, state) { sdSend({ event: 'setState', context: ctx, payload: { state } }); }
function setTitle(ctx, title) { sdSend({ event: 'setTitle', context: ctx, payload: { title, target: 0 } }); }
function setImage(ctx, image) { sdSend({ event: 'setImage', context: ctx, payload: { image, target: 0 } }); }
function alertKey(ctx) { sdSend({ event: 'showAlert', context: ctx }); }

const imgCache = new Map();
function keyImage(name) {
  if (!imgCache.has(name)) {
    let data = null;
    try { data = 'data:image/png;base64,' + fs.readFileSync(path.join(KEY_IMG_DIR, name + '.png')).toString('base64'); } catch (e) { log('missing key image', name); }
    imgCache.set(name, data);
  }
  return imgCache.get(name);
}
function wrapTitle(s, width = 10, maxLines = 3) {
  const words = String(s || '').trim().split(/\s+/).filter(Boolean);
  const lines = []; let cur = '';
  for (let w of words) {
    while (w.length > width) { if (cur) { lines.push(cur); cur = ''; } lines.push(w.slice(0, width)); w = w.slice(width); }
    if (!cur) cur = w; else if ((cur + ' ' + w).length <= width) cur += ' ' + w; else { lines.push(cur); cur = w; }
  }
  if (cur) lines.push(cur);
  return lines.slice(0, maxLines).join('\n');
}
function viewFor(k) {
  const s = k.settings || {};
  const mode = (s.mode === undefined || s.mode === 'auto' || s.mode === '') ? (cam().mode === null ? 0 : cam().mode) : Number(s.mode);
  const slot = Math.max(1, Math.min(99, parseInt(s.slot, 10) || 1));
  return { mode, slot, view: viewsForMode(mode)[slot - 1] || null };
}
function once(k, field, value, fn) { if (k.sent[field] !== value) { k.sent[field] = value; fn(value); } }
function render(ctx) {
  const k = keys.get(ctx);
  if (!k) return;
  k.sent = k.sent || {};
  if (k.id === 'view') {
    const { mode, view } = viewFor(k);
    let img, title;
    if (!bridge.ready) { img = 'view_offline'; title = ''; }
    else if (!view) { img = 'view_empty'; title = ''; }
    else { const lit = !!(model.camera && model.camera.preset_guid === view.guid); img = `view_m${Math.min(2, Math.max(0, mode))}${lit ? '_lit' : ''}`; title = wrapTitle(view.name); }
    once(k, 'img', img, (n) => { const d = keyImage(n); if (d) setImage(ctx, d); });
    once(k, 'title', title, (t) => setTitle(ctx, t));
  } else if (k.id === 'status') {
    const on = bridge.ready;
    once(k, 'state', on ? 1 : 0, (s) => setState(ctx, s));
    const m = cam().mode;
    const title = on ? (MODE_NAMES[m] || 'ONLINE') + (model.aircraft ? '\n' + wrapTitle(model.aircraft, 12, 2) : '') : 'BRIDGE\nOFFLINE';
    once(k, 'title', title, (t) => setTitle(ctx, t));
  } else if (STATIC[k.id]) {
    let lit = false;
    try { lit = bridge.ready && STATIC[k.id].lit(); } catch (e) { lit = false; }
    once(k, 'state', lit ? 1 : 0, (s) => setState(ctx, s));
  } else if (k.id === 'cmd') {
    const s = k.settings || {};
    if (CMD_LIT[s.command]) {
      let lit = false;
      try { lit = bridge.ready && CMD_LIT[s.command](); } catch (e) { lit = false; }
      once(k, 'state', lit ? 1 : 0, (st) => setState(ctx, st));
    }
    // keys made with the settings page can show the command's name; keys from the profiles carry their own label in the picture
    if (s.autoTitle && s.command) { const info = commandInfo(s.command); k.titled = true; once(k, 'title', wrapTitle(info ? info.title : s.command, 10, 3), (t) => setTitle(ctx, t)); }
    else if (k.titled) { k.titled = false; k.sent.title = ''; setTitle(ctx, ''); }        // the option was switched off: take our title away again
  }
}
function renderAll() { for (const ctx of keys.keys()) render(ctx); }

async function onKeyDown(ctx) {
  const k = keys.get(ctx);
  if (!k) return;
  if (k.id === 'status') { return; }
  if (k.id === 'cmd') {           // works without the Bridge too: it only needs to know the key the user bound
    k.isDown = true;
    try { await commandDown(ctx, k); } catch (e) { log('action failed', 'cmd', (k.settings || {}).command, String(e)); alertKey(ctx); }
    return;
  }
  if (!bridge.ready) { log('key pressed while Bridge offline:', k.id); alertKey(ctx); return; }
  try {
    if (k.id === 'view') {
      const { view } = viewFor(k);
      if (!view) { log('empty view slot pressed', k.settings); alertKey(ctx); return; }
      await selectView(view);
    } else if (STATIC[k.id]) {
      await STATIC[k.id].run();
    }
  } catch (e) {
    log('action failed', k.id, String(e));
    alertKey(ctx);
  }
}

function onSD(text) {
  let m;
  try { m = JSON.parse(text); } catch (e) { return; }
  switch (m.event) {
    case 'willAppear':
      keys.set(m.context, { id: String(m.action || '').slice(PREFIX.length), settings: (m.payload && m.payload.settings) || {}, sent: {} });
      render(m.context);
      break;
    case 'willDisappear': releaseHeld(m.context); keys.delete(m.context); break;
    case 'keyUp': { const k = keys.get(m.context); if (k) k.isDown = false; releaseHeld(m.context); break; }
    case 'didReceiveSettings': {
      const k = keys.get(m.context);
      if (k) { k.settings = (m.payload && m.payload.settings) || {}; k.sent = {}; render(m.context); }
      break;
    }
    case 'keyDown': onKeyDown(m.context); break;
    case 'sendToPlugin':
      if (m.payload && m.payload.request === 'commands') {          // settings page of the "ChasePlane command" key
        refreshBindings(false).then(() => {
          const l = commandList();
          sdSend({ event: 'sendToPropertyInspector', action: m.action, context: m.context, payload: Object.assign({ online: bridge.ready, source: l.source, commands: l.commands }) });
        });
      } else if (m.payload && m.payload.request === 'views') {
        const mode = m.payload.mode === undefined || m.payload.mode === 'auto' ? (cam().mode === null ? 0 : cam().mode) : Number(m.payload.mode);
        sdSend({ event: 'sendToPropertyInspector', action: m.action, context: m.context,
                 payload: { online: bridge.ready, aircraft: model.aircraft, mode, names: viewsForMode(mode).map((v) => v.name) } });
      }
      break;
    default: break;
  }
}

function parseArgs(argv) {
  const o = {};
  for (let i = 0; i < argv.length - 1; i += 2) o[argv[i].replace(/^-+/, '')] = argv[i + 1];
  return o;
}
function main() {
  const a = parseArgs(process.argv.slice(2));
  if (!a.port || !a.pluginUUID || !a.registerEvent) { log('missing Stream Deck arguments', process.argv.slice(2)); process.exit(1); }
  log('plugin starting; node', process.version, 'bridge', BRIDGE_URL);
  sd = new WS('ws://127.0.0.1:' + a.port);
  sd.on('open', () => {
    sd.send(JSON.stringify({ event: a.registerEvent, uuid: a.pluginUUID }));
    connectBridge();
    refreshBindings(true);                                           // from ChasePlane's settings file until the Bridge answers
    setInterval(() => { if (bridge.ready) refreshBindings(true); }, 60000).unref();      // pick up shortcuts the user changes while flying
  });
  sd.on('message', onSD);
  sd.on('error', (e) => log('Stream Deck socket error', String(e)));
  sd.on('close', () => { log('Stream Deck socket closed, exiting'); releaseAll(); process.exit(0); });
}
if (require.main === module) main();
else module.exports = { parseMappingText, extractBindings, vksOfEntries, flattenEvents, vkName, comboName };       // for the tests
