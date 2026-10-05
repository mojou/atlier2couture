import puppeteer from 'puppeteer-core';
import { pathToFileURL } from 'node:url';
const b = await puppeteer.launch({ executablePath: 'C:\\\\Program Files\\\\Google\\\\Chrome\\\\Application\\\\chrome.exe', headless: true });
const p = await b.newPage();
for (const [n, w, h] of [['pc', 1280, 900], ['tel', 390, 1500]]) {
  await p.setViewport({ width: w, height: h });
  await p.goto(pathToFileURL('../site-web/index.html').href, { waitUntil: 'networkidle0' });
  await p.evaluate(() => { document.querySelectorAll('.apparition').forEach(e => e.classList.add('visible')); document.getElementById('video').scrollIntoView(); });
  await new Promise(r => setTimeout(r, 2500));
  await p.screenshot({ path: process.env.TEMP + '/vid/landing-' + n + '.png' });
}
await b.close();
