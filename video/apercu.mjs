// Images-tests du film : node apercu.mjs (enregistre quelques instants dans %TEMP%\vid)
import puppeteer from 'puppeteer-core';
import { pathToFileURL } from 'node:url';
const b = await puppeteer.launch({ executablePath: 'C:\\\\Program Files\\\\Google\\\\Chrome\\\\Application\\\\chrome.exe', headless: true });
const p = await b.newPage(); await p.setViewport({ width: 720, height: 1280 });
await p.goto(pathToFileURL('scene.html').href + '?rendu=1', { waitUntil: 'networkidle0' }); await p.evaluate(() => document.fonts.ready);
for (const t of [2, 6.5, 11, 15.8, 19.5, 24]) { await p.evaluate(t => allerA(t), t); await p.screenshot({ path: process.env.TEMP + '/vid/t' + t + '.png' }); }
await b.close();
