// Renders video/demo.html to MP4, frame by frame, with Playwright and ffmpeg.
//
//   node video/render.mjs [out.mp4] [--stills 3,7.2,10]
//
// Each frame calls render(t) in the page, so timing is exact regardless of how
// long a screenshot takes.
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let playwright;
try { playwright = require('playwright'); } catch { playwright = require('/opt/node-tools/node_modules/playwright'); }

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const stillsArg = args.indexOf('--stills');
const stills = stillsArg >= 0 ? args[stillsArg + 1].split(',').map(Number) : null;
const out = resolve(args.find(a => a.endsWith('.mp4')) ?? resolve(here, '../site/assets/demo.mp4'));
const fps = 30, scale = 1;

const browser = await playwright.chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: scale });
await page.goto('file://' + resolve(here, 'demo.html'));
await page.evaluate(() => document.fonts.ready);
const total = await page.evaluate(() => window.TOTAL);

if (stills) {
  mkdirSync(resolve(here, 'stills'), { recursive: true });
  for (const t of stills) {
    await page.evaluate(t => window.render(t), t);
    writeFileSync(resolve(here, `stills/t${t}.png`), await page.screenshot());
  }
  await browser.close();
  console.log('Wrote stills to video/stills/');
  process.exit(0);
}

const ffmpeg = spawn('ffmpeg', [
  '-y', '-loglevel', 'error',
  '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '24', '-pix_fmt', 'yuv420p',
  '-movflags', '+faststart', '-an', out,
], { stdio: ['pipe', 'inherit', 'inherit'] });

const frames = Math.round(total * fps);
for (let i = 0; i < frames; i++) {
  await page.evaluate(t => window.render(t), i / fps);
  const buf = await page.screenshot({ type: 'jpeg', quality: 92 });
  if (!ffmpeg.stdin.write(buf)) await new Promise(r => ffmpeg.stdin.once('drain', r));
  if (i % 60 === 0) process.stdout.write(`frame ${i}/${frames}\r`);
}
ffmpeg.stdin.end();
await new Promise(r => ffmpeg.on('close', r));
await browser.close();
console.log(`\nWrote ${out}`);
