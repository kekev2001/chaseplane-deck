'use strict';
// ChasePlane Deck - Stream Deck plugin that talks to ChasePlane's local Bridge API (ws://127.0.0.1:8652).
// No dependencies: a small RFC 6455 WebSocket client is included below and used for both the Stream Deck
// connection and the Bridge connection. The Bridge API is undocumented; message names were read from the
// Bridge's own web UI ("ChasePlane Remote"), see README.
const net = require('net');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { EventEmitter } = require('events');

const BRIDGE_URL = process.env.CHASEPLANE_BRIDGE_URL || 'ws://127.0.0.1:8652';
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
const model = { camera: null, runtime: null, views: [], aircraft: '' };
let viewsTimer = null;

function cam() { return model.camera || { mode: null }; }
function flag(names) {
  for (const src of [model.camera, model.runtime]) {
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
  }
}
function renderAll() { for (const ctx of keys.keys()) render(ctx); }

async function onKeyDown(ctx) {
  const k = keys.get(ctx);
  if (!k) return;
  if (k.id === 'status') { return; }
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
    case 'willDisappear': keys.delete(m.context); break;
    case 'didReceiveSettings': {
      const k = keys.get(m.context);
      if (k) { k.settings = (m.payload && m.payload.settings) || {}; k.sent = {}; render(m.context); }
      break;
    }
    case 'keyDown': onKeyDown(m.context); break;
    case 'sendToPlugin':
      if (m.payload && m.payload.request === 'views') {
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
  sd.on('open', () => { sd.send(JSON.stringify({ event: a.registerEvent, uuid: a.pluginUUID })); connectBridge(); });
  sd.on('message', onSD);
  sd.on('error', (e) => log('Stream Deck socket error', String(e)));
  sd.on('close', () => { log('Stream Deck socket closed, exiting'); process.exit(0); });
}
main();
