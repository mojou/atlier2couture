// Aperçu local du dossier site-web/ (landing page + application dans /app/).
// Usage : node apercu-site.js   puis ouvrir http://localhost:5090
const http = require('http');
const fs = require('fs');
const path = require('path');

const racine = path.join(__dirname, 'site-web');
const port = Number(process.argv[2] || 5090);
const types = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm', '.otf': 'font/otf', '.ttf': 'font/ttf', '.ico': 'image/x-icon',
  '.apk': 'application/vnd.android.package-archive',
};

http.createServer((req, res) => {
  let fichier = path.join(racine, decodeURIComponent(req.url.split('?')[0]));
  if (!fichier.startsWith(racine)) { res.writeHead(403); return res.end(); }
  if (fs.existsSync(fichier) && fs.statSync(fichier).isDirectory()) fichier = path.join(fichier, 'index.html');
  if (!fs.existsSync(fichier)) { res.writeHead(404); return res.end('Introuvable'); }
  res.writeHead(200, { 'Content-Type': types[path.extname(fichier)] || 'application/octet-stream' });
  fs.createReadStream(fichier).pipe(res);
}).listen(port, () => console.log(`Aperçu sur http://localhost:${port}`));
