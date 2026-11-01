'use strict';
// Stand-in for plugin\...\bin\keysend.exe in the tests: writes every command it receives to the file named in CPDECK_KEYSEND_LOG and
// answers "ok". It never presses a real key, so the tests cannot type into whatever window happens to be open.
const fs = require('fs');
const log = process.env.CPDECK_KEYSEND_LOG;
if (log) fs.appendFileSync(log, 'args: ' + process.argv.slice(2).join(' ') + '\n');
let buf = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
    if (!line) continue;
    if (log) fs.appendFileSync(log, line + '\n');
    // like the real helper with --require-foreground when another window is in front: "down" and "tap" are refused, the rest works
    const refuse = process.env.CPDECK_KEYSEND_REFUSE && fs.existsSync(process.env.CPDECK_KEYSEND_REFUSE) && /^(down|tap)\b/.test(line);
    process.stdout.write(refuse ? 'err not-foreground notepad\n' : 'ok\n');
  }
});
process.stdin.on('end', () => { if (log) fs.appendFileSync(log, '<stdin closed>\n'); });
