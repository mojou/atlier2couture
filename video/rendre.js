// Filme scene.html image par image avec Chrome, puis assemble un MP4 avec ffmpeg.
// Usage (dans le dossier video) : node rendre.js
//  -> Atelier-Couture-video-fr.mp4 / -en.mp4 (1080 x 1920, statut WhatsApp)
//  -> ../landing/video-demo.mp4 + video-demo.jpg (720 x 1280, page d'accueil)
import { spawn } from "node:child_process";
import { pathToFileURL } from "node:url";
import path from "node:path";
import puppeteer from "puppeteer-core";
import ffmpeg from "ffmpeg-static";

const ICI = path.dirname(new URL(import.meta.url).pathname.replace(/^\/(\w:)/, "$1"));
const CHROME = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const IPS = 30;

function encoder(sortie, args) {
  const p = spawn(ffmpeg, ["-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(IPS), "-i", "-", ...args, sortie]);
  p.stderr.on("data", d => process.stderr.write(d));
  const fini = new Promise((ok, ko) => p.on("close", c => (c === 0 ? ok() : ko(new Error(`ffmpeg ${c}`)))));
  return { entree: p.stdin, fini };
}

async function filmer(navigateur, langue) {
  const page = await navigateur.newPage();
  await page.setViewport({ width: 720, height: 1280, deviceScaleFactor: 1.5 });
  const url = pathToFileURL(path.join(ICI, "scene.html")).href + `?rendu=1&lang=${langue}`;
  await page.goto(url, { waitUntil: "networkidle0" });
  await page.evaluate(() => document.fonts.ready);
  const duree = await page.evaluate(() => window.DUREE);

  const commun = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "slow", "-movflags", "+faststart"];
  const sorties = [encoder(path.join(ICI, `Atelier-Couture-video-${langue}.mp4`), [...commun, "-crf", "22"])];
  if (langue === "fr") {
    sorties.push(encoder(path.join(ICI, "..", "landing", "video-demo.mp4"), ["-vf", "scale=720:1280", ...commun, "-crf", "27"]));
  }

  const n = Math.round(duree * IPS);
  for (let i = 0; i < n; i++) {
    await page.evaluate(t => window.allerA(t), i / IPS);
    const image = await page.screenshot({ type: "jpeg", quality: 92 });
    for (const s of sorties) {
      if (!s.entree.write(image)) await new Promise(r => s.entree.once("drain", r));
    }
    if (langue === "fr" && i === Math.round(23.5 * IPS)) {
      await page.screenshot({ path: path.join(ICI, "..", "landing", "video-demo.jpg"), type: "jpeg", quality: 80, clip: undefined });
    }
    if (i % 150 === 0) console.log(`${langue} : ${Math.round((i / n) * 100)} %`);
  }
  sorties.forEach(s => s.entree.end());
  await Promise.all(sorties.map(s => s.fini));
  await page.close();
  console.log(`${langue} : terminé`);
}

const navigateur = await puppeteer.launch({ executablePath: CHROME, headless: true, args: ["--hide-scrollbars"] });
try {
  for (const langue of process.argv.slice(2).length ? process.argv.slice(2) : ["fr", "en"]) await filmer(navigateur, langue);
} finally {
  await navigateur.close();
}
