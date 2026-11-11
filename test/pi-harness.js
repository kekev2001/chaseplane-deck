'use strict';
// Serves the settings page of the "ChasePlane command" key (ui/cmd.html) the way the Stream Deck app would run it, with a fake Stream Deck app behind it,
// so the page can be tried in any browser:   node test\pi-harness.js        then open  http://127.0.0.1:18700/pi.html   (?offline=1 = Bridge not running)
//   /log    shows what the page sent to the "plugin" (sendToPlugin requests and the settings it saved)
// Needs the "ws" package (CP_TEST_WS or npm install ws), like plugin-test.js.
const http = require('http');
const fs = require('fs');
const path = require('path');
function loadWs() {
  for (const c of [process.env.CP_TEST_WS, 'ws', path.join(__dirname, 'node_modules', 'ws')].filter(Boolean)) { try { return require(c); } catch (e) { /* next */ } }
  console.error('The "ws" package is needed: set CP_TEST_WS or run npm install ws'); process.exit(2);
}
const { Server: WSServer } = loadWs();
const UI = path.join(__dirname, '..', 'plugin', 'com.chaseplanexl.deck.sdPlugin', 'ui', 'cmd.html');
const KNOWN = path.join(__dirname, '..', 'plugin', 'com.chaseplanexl.deck.sdPlugin', 'bin', 'known-commands.json');
const HTTP_PORT = Number(process.env.PI_PORT || 18700);
const log = [];

const known = fs.existsSync(KNOWN) ? JSON.parse(fs.readFileSync(KNOWN, 'utf8')) : [];
const KEYS = { CAM_QUICK_VIEW_LEFT: 'Shift+H', CAM_QUICK_VIEW_UP: 'Ctrl+Alt+F7', CAM_ZOOM_IN: 'Shift+O', CAM_BOOST_SET: 'PageUp', CAM_ROLL_L: 'Ctrl+Alt+4' };
function bridgeList() {
  const cats = ['Camera Movements', 'Camera Actions', 'ChasePlane Features'];
  return known.map((c, i) => ({ id: c.id, title: c.title, category: cats[i % cats.length], description: 'Description of ' + c.title + '.', bridge: /CONTROL_PROFILE/.test(c.id), key: KEYS[c.id] || null }));
}
let nextOffline = false;                       // set when a page is served; the page's socket picks it up when it connects
const wss = new WSServer({ port: HTTP_PORT + 1, host: '127.0.0.1' });
wss.on('connection', (ws) => {
  ws.offline = nextOffline;
  ws.on('message', (data) => {
    const m = JSON.parse(String(data));
    log.push(m);
    if (m.event === 'sendToPlugin' && m.payload && m.payload.request === 'commands') {
      const offline = ws.offline;
      const commands = offline ? known.map((c) => ({ id: c.id, title: c.title, category: c.category, description: '', bridge: /CONTROL_PROFILE/.test(c.id), key: null })) : bridgeList();
      ws.send(JSON.stringify({ event: 'sendToPropertyInspector', action: m.action, context: m.context, payload: { online: !offline, source: offline ? 'built-in' : 'bridge', commands } }));
    }
  });
});
http.createServer((req, res) => {
  const u = new URL(req.url, 'http://127.0.0.1');
  if (u.pathname === '/log') { res.setHeader('content-type', 'application/json'); res.end(JSON.stringify(log)); return; }
  if (u.pathname === '/narrow') {              // the same page in a 290 px wide frame, like the settings area of the Stream Deck app
    res.setHeader('content-type', 'text/html; charset=utf-8');
    res.end('<body style="margin:0;background:#1d1d1d"><iframe src="/pi.html' + u.search + '" style="width:290px;height:720px;border:1px solid #555;margin:10px"></iframe></body>');
    return;
  }
  if (u.pathname === '/pi.html') {
    const offline = u.searchParams.get('offline') === '1';
    const settings = u.searchParams.get('settings') ? JSON.parse(u.searchParams.get('settings')) : {};
    let html = fs.readFileSync(UI, 'utf8');
    const boot = `<script>window.addEventListener('load', function () { connectElgatoStreamDeckSocket(${HTTP_PORT + 1}, 'PI-UUID', 'registerPropertyInspector', '{}', ${JSON.stringify(JSON.stringify({ action: 'com.chaseplanexl.deck.cmd', context: 'CTX', payload: { settings } }))}); });</script>`;
    html = html.replace('</body>', boot + '</body>');
    res.setHeader('content-type', 'text/html; charset=utf-8');
    nextOffline = offline;
    res.end(html);
    return;
  }
  res.statusCode = 404; res.end('not found');
}).listen(HTTP_PORT, '127.0.0.1', () => console.log('PI harness on http://127.0.0.1:' + HTTP_PORT + '/pi.html'));
